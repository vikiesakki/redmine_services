module IssueQueryPatch
  def self.included(base)
    base.send :include, InstanceMethods
    base.class_eval do
      self.available_columns << QueryColumn.new(:checkin_time)
      self.available_columns << QueryColumn.new(:checkout_time)
    end
  end
  
  module  InstanceMethods
  end
end
unless IssueQuery.included_modules.include? IssueQueryPatch
  IssueQuery.send :include, IssueQueryPatch
end
