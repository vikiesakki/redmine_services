class IssueLinkHook < Redmine::Hook::ViewListener
	render_on :view_issues_show_description_bottom,
                partial: 'hooks/issue_share_link'
    render_on :view_issues_form_details_bottom
    			partial: 'hooks/_issue_add_func'
end