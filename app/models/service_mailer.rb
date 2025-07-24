class ServiceMailer < ActionMailer::Base
  
  layout 'mailer'
  helper :application
  helper :issues
  helper :custom_fields

  include Redmine::I18n
  include Roadie::Rails::Automatic

	def self.deliver_service_success_notification(to, issue)
  	send_service_success_notification(to, issue)
	end

  def self.deliver_day_reminder(user,issues)
    send_day_reminder(user,issues)
  end

  def self.deliver_week_reminder(project, issues)
    send_week_reminder(project,issues)
  end

  def send_service_success_notification(to, issue)
    @issue = issue
    subj = "Service Completed – Ref Number #[#{issue.id}]"
    pdf_html = ApplicationController.render(
      template: 'services/report_pdf',
      layout: 'pdf', # optional: use layouts/pdf.html.erb
      assigns: { issue: @issue }
    )
    pdf_file = WickedPdf.new.pdf_from_string(pdf_html)
    attachments["service_report_#{issue.id}.pdf"] = {
      mime_type: 'application/pdf',
      content: pdf_file
    }
    @issue_url = url_for(:controller => 'issues', :action => 'show', :id => issue)
    mail :to => to,
      :subject => subj
  end

  def send_day_reminder(user,issues)
    @iss_arry = []
    @managers = []
    @user = user
    issues.each do |issue|
      puts "*******processing the issue ##{issue.id}************"
      _h = {}
      _h[:id] = "##{issue.id}"
      _h[:subject] = issue.subject
      _h[:project] = issue.project
      _h[:status] = issue.status.try(:name)
      _h[:priority] = issue.priority.name
      _h[:issue_url] = url_for(:controller => 'issues', :action => 'show', :id => issue)
      _h[:due_date] = issue.due_date
      @iss_arry << _h
      members = issue.project.memberships
      members.each do |mem|
        if mem.roles.map(&:name).include?("Manager") || mem.roles.map(&:name).include?("Project Manager")
          @managers << mem.user
        end
      end
    end
    cc = @managers.compact.uniq.map(&:mail) + User.where(admin: 1).map(&:mail)
    @admins = User.where(admin: 1).to_a
    puts "*********cc#{cc}******#{user.mail}"
    subj = "Daily Reminder – Pending Redmine Tickets for Your Action"
    mail :to => user.mail, cc: cc.uniq,
      :subject => subj
  end


  def send_notification(email_history)
  	issue = email_history.issue
    # journal = email_history
    redmine_headers 'Project' => issue.project.identifier,
                    'Issue-Tracker' => issue.tracker.name,
                    'Issue-Id' => issue.id,
                    'Issue-Author' => issue.author.login

    message_id issue
    references issue
    @author = email_history.user
    @history = email_history
    s = "[#{issue.project.name} - #{issue.tracker.name} ##{issue.id}] "
    s += issue.subject
    @issue = issue
    @user = email_history.user
    # @journal = journal
    # @journal_details = journal.visible_details
    @issue_url = url_for(:controller => 'issues', :action => 'show', :id => issue)

    mail :to => email_history.to_email,
      :subject => email_history.subject
  end

  def self.default_url_options
    options = {:protocol => Setting.protocol}
    if Setting.host_name.to_s =~ /\A(https?\:\/\/)?(.+?)(\:(\d+))?(\/.+)?\z/i
      host, port, prefix = $2, $4, $5
      options.merge!(
        {
          :host => host, :port => port, :script_name => prefix
        }
      )
    else
      options[:host] = Setting.host_name
    end
    options
  end

  def mail(headers={}, &block)
    # Add a display name to the From field if Setting.mail_from does not
    # include it
    begin
      mail_from = Mail::Address.new(Setting.mail_from)
      if mail_from.display_name.blank? && mail_from.comments.blank?
        mail_from.display_name =
          @author&.logged? ? @author.name : Setting.app_title
      end
      from = mail_from.format
      list_id = "<#{mail_from.address.to_s.tr('@', '.')}>"
    rescue Mail::Field::IncompleteParseError
      # Use Setting.mail_from as it is if Mail::Address cannot parse it
      # (probably the emission address is not RFC compliant)
      from = Setting.mail_from.to_s
      list_id = "<#{from.tr('@', '.')}>"
    end

    headers.reverse_merge! 'X-Mailer' => 'Redmine',
            'X-Redmine-Host' => Setting.host_name,
            'X-Redmine-Site' => Setting.app_title,
            'X-Auto-Response-Suppress' => 'All',
            'Auto-Submitted' => 'auto-generated',
            'From' => from,
            'List-Id' => list_id

    # Replaces users with their email addresses
    # [:to, :cc, :bcc].each do |key|
    #   if headers[key].present?
    #     headers[key] = headers[key]
    #   end
    # end

    # Removes the author from the recipients and cc
    # if the author does not want to receive notifications
    # about what the author do
    if @author&.logged? && @author.pref.no_self_notified
      addresses = @author.mails
      headers[:to] -= addresses if headers[:to].is_a?(Array)
      headers[:cc] -= addresses if headers[:cc].is_a?(Array)
    end

    if @author&.logged?
      redmine_headers 'Sender' => @author.login
    end

    if @message_id_object
      headers[:message_id] = "<#{self.class.message_id_for(@message_id_object, @user)}>"
    end
    if @references_objects
      headers[:references] = @references_objects.collect {|o| "<#{self.class.references_for(o, @user)}>"}.join(' ')
    end

    if block_given?
      super headers, &block
    else
      super headers do |format|
        format.text
        format.html unless Setting.plain_text_mail?
      end
    end
  end

  private

  def message_id_for(object, user)
      token_for(object, user)
    end

  def redmine_headers(h)
    h.compact.each {|k, v| headers["X-Redmine-#{k}"] = v.to_s}
  end

  class << self
    def token_for(object, user)
      timestamp = object.send(object.respond_to?(:created_on) ? :created_on : :updated_on)
      hash = [
        "redmine",
        "#{object.class.name.demodulize.underscore}-#{object.id}",
        timestamp.utc.strftime("%Y%m%d%H%M%S")
      ]
      hash << user.id if user
      host = Setting.mail_from.to_s.strip.gsub(%r{^.*@|>}, '')
      host = "#{::Socket.gethostname}.redmine" if host.empty?
      "#{hash.join('.')}@#{host}"
    end

    # Returns a Message-Id for the given object
    def message_id_for(object, user)
      token_for(object, user)
    end

    # Returns a uniq token for a given object referenced by all notifications
    # related to this object
    def references_for(object, user)
      token_for(object, user)
    end
  end

  def message_id(object)
    @message_id_object = object
  end

  def references(object)
    @references_objects ||= []
    @references_objects << object
  end

end
