require 'redmine'
$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/lib/"
require 'issue_link_hook'
require 'issue_patch'
require 'issue_query_patch'
Redmine::Plugin.register :redmine_services do
  name 'Redmine Services plugin'
  author 'Vignesh EsakkiMuthu'
  description 'This is a plugin for Redmine to customize Services'
  version '0.0.1'
  url 'https://redmineconsultation.com'
  settings default: {}, partial: 'settings/services'
end
