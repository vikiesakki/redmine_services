require 'active_support/message_encryptor'
require 'base64'
module IssuePatch
  def self.included(base)
    base.send :include, InstanceMethods
    base.extend ClassMethods
    base.class_eval do
    end
  end

  module ClassMethods
    def decrypt_id_from_url(encoded_id)
      encrypted = Base64.urlsafe_decode64(encoded_id)
      ActiveSupport::MessageEncryptor.new(Issue.enckey).decrypt_and_verify(encrypted)
    end

    def enckey
      Rails.application.credentials.secret_key_base[0..31]
    end
  end

  module InstanceMethods
    def encrypt_id_for_url
      encrypted = ActiveSupport::MessageEncryptor.new(Issue.enckey).encrypt_and_sign(id.to_s)
      Base64.urlsafe_encode64(encrypted)
    end

    def checkin_time(time_zone = User.current.time_zone)
      check_in_time.present? ? Time.parse(check_in_time).in_time_zone(time_zone).strftime("%d-%m-%Y %H:%M:%S") : ''
    end
  
    def checkout_time(time_zone = User.current.time_zone)
      check_out_time.present? ? Time.parse(check_out_time).in_time_zone(time_zone).strftime("%d-%m-%Y %H:%M:%S") : ''
    end

  end
end
unless Issue.included_modules.include? IssuePatch
  Issue.send :include, IssuePatch
end
