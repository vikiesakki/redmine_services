class ServicesController < ApplicationController
	layout 'services'
	skip_before_action :verify_authenticity_token, only: :upload
	skip_before_action :session_expiration, :user_setup, :check_if_login_required, :check_password_change, :check_twofa_activation
	
	helper :issues
	helper :journals
	helper :projects
	helper :custom_fields
	helper :issue_relations
	helper :watchers
	helper :attachments
	helper :queries
	include QueriesHelper
	helper :repositories
	helper :timelog

	def form
		encid = params[:issue_id]
		issue_id = Issue.decrypt_id_from_url(encid)
		@issue = Issue.find_by_id issue_id
		if @issue.blank?
			raise ::Unauthorized
		end
		render :form_submit if @issue.check_out_time.present?
	end

	def checkin
		encid = params[:issue_id]
		issue_id = Issue.decrypt_id_from_url(encid)
		@issue = Issue.find_by_id issue_id
		if @issue.blank?
			raise ::Unauthorized
		else
			@issue.update(check_in_time: Time.now,status_id: 2)
			redirect_to service_form_path(issue_id: params[:issue_id])
		end
	end

	def upload
    # Make sure that API users get used to set this content type
    # as it won't trigger Rails' automatic parsing of the request body for parameters
    unless request.media_type == 'application/octet-stream'
      head :not_acceptable
      return
    end

    @attachment = Attachment.new(:file => raw_request_body)
    @attachment.author = User.current
    @attachment.filename = params[:filename].presence || Redmine::Utils.random_hex(16)
    @attachment.content_type = params[:content_type].presence
    saved = @attachment.save

    respond_to do |format|
      format.js
    end
	end

  def report_pdf
  	@issue = Issue.find params[:id]
  end

	def form_submit
		@issue = Issue.find_by_id params[:issue_id]
		if @issue.check_out_time.blank?
			base64_data = params[:signature_data]
			attach_signature_to_issue(@issue, base64_data) if base64_data.present?
			save_issue_custom_field_values
			save_issue_attachments
			save_service_report
			# attachments = params[:attachments] || params.dig(:issue, :uploads)
				update_status = params[:issue][:status_id] || 5
		    @issue.update(check_out_time: Time.now,status_id: update_status)
		    send_issue_notifications
		end
	end

  def download
    @attachment = Attachment.find params[:id]
    if @attachment.container.is_a?(Version) || @attachment.container.is_a?(Project)
      @attachment.increment_download
    end

    if stale?(:etag => @attachment.digest, :template => false)
      # images are sent inline
      send_file @attachment.diskfile, :filename => filename_for_content_disposition(@attachment.filename),
                                :type => detect_content_type(@attachment),
                                :disposition => disposition(@attachment)
    end
  end

	private
	def save_service_report
	pdf_html = ApplicationController.render(
      template: 'services/report_pdf',
      layout: 'pdf', # optional: use layouts/pdf.html.erb
      assigns: { issue: @issue }
    )
    pdf_file = WickedPdf.new.pdf_from_string(pdf_html)
    attachment = Attachment.create!(
      container: @issue,
      file: StringIO.new(pdf_file),
      filename: "service_report_#{@issue.id}.pdf",
      author: ,
      content_type: 'application/pdf'
    )
  end

	def raw_request_body
	    if request.body.respond_to?(:size)
	      request.body
	    else
	      request.raw_post
	    end
  	end

  	def save_issue_attachments
  		return if params[:attachments].blank?
  		atts = params[:attachments]
  		atts.each do |ak,av|
  			next if av[:token].blank?
  			a = Attachment.find_by_token av[:token]
  			next if a.blank?
  			a.update(container_id: @issue.id, container_type: 'Issue')
  		end
  	end

  	def send_issue_notifications
  		group_emails = []
  		Setting.plugin_redmine_services['notify_groups'].to_a.each do |ng|
  			gg = Group.find ng
  			group_emails << gg.users.map(&:mail)
  		end
  		group_emails = group_emails.flatten.uniq
  		ServiceMailer.deliver_service_success_notification(group_emails, @issue).deliver_now if group_emails.present?
  		notify_persons = Setting.plugin_redmine_services['notify_persons'].to_s.split(',')
  		ServiceMailer.deliver_service_success_notification(notify_persons, @issue).deliver_now if notify_persons.present?
  		notify_emails = []
  		Setting.plugin_redmine_services['notify_fields'].to_a.each do |nu|
  			if (@issue.custom_field_value(nu).to_s =~ URI::MailTo::EMAIL_REGEXP).present?
  				notify_emails << @issue.custom_field_value(nu)
  			end
  		end
  		notify_emails = notify_emails.uniq
  		ServiceMailer.deliver_service_success_notification(notify_emails, @issue).deliver_now if notify_emails.present?
  	end

	def save_issue_custom_field_values
		cv_values = params[:issue].present? ? params[:issue][:custom_field_values] : {}
		cv_values.keys.each do |k|
			cv = CustomValue.where(customized_type: 'Issue', customized_id: @issue.id, custom_field_id: k).first
			if cv.present?
				cv.update(value: cv_values[k])
			else
				CustomValue.create(value: cv_values[k], customized_type: 'Issue', customized_id: @issue.id, custom_field_id: k)
			end
		end
	end

	def save_issue_with_child_records
	    Issue.transaction do
	      if params[:time_entry] &&
	           (params[:time_entry][:hours].present? || params[:time_entry][:comments].present?) &&
	           User.current.allowed_to?(:log_time, @issue.project)
	        time_entry = @time_entry || TimeEntry.new
	        time_entry.project = @issue.project
	        time_entry.issue = @issue
	        time_entry.author = User.current
	        time_entry.user = User.current
	        time_entry.spent_on = User.current.today
	        time_entry.safe_attributes = params[:time_entry]
	        @issue.time_entries << time_entry
	      end
	      call_hook(
	        :controller_issues_edit_before_save,
	        {:params => params, :issue => @issue,
	         :time_entry => time_entry,
	         :journal => @issue.current_journal}
	      )
	      if @issue.save
	        call_hook(
	          :controller_issues_edit_after_save,
	          {:params => params, :issue => @issue,
	           :time_entry => time_entry,
	           :journal => @issue.current_journal}
	        )
	      else
	        raise ActiveRecord::Rollback
	      end
	    end
	end

  	def attach_signature_to_issue(issue, base64_data)
	  return if base64_data.blank?

	  image_data = base64_data.sub(/^data:image\/png;base64,/, '')
	  decoded_image = Base64.decode64(image_data)

	  # Build a sanitized Tempfile
	  tempfile = Tempfile.new(["signature_#{issue.id}", '.png'], binmode: true)
	  tempfile.write(decoded_image)
	  tempfile.rewind

	  file = {
	    tempfile: tempfile,
	    filename: "signature_#{issue.id}.png",
	    type: "image/png"
	  }

	  attachment = Attachment.create!(
	    container: issue,
	    file: file[:tempfile],
	    filename: file[:filename],
	    author: User.current,
	    content_type: file[:type]
	  )

	  tempfile.close
	end

        def detect_content_type(attachment, is_thumb = false)
          content_type = attachment.content_type
          if content_type.blank? || content_type == "application/octet-stream"
            content_type =
              Redmine::MimeType.of(attachment.filename).presence ||
                "application/octet-stream"
          end

          if is_thumb && content_type == "application/pdf"
            # PDF previews are stored in PNG format
            content_type = "image/png"
          end

          content_type
       end

        def disposition(attachment)
          if attachment.is_pdf?
            'inline'
          else
            'attachment'
          end
      end

end
