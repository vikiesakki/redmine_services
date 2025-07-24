# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html
match 'service/upload', as: 'service_upload', to: "services#upload", via: [:post]
match 'service/:issue_id', as: 'service_form', to: "services#form", via: [:get, :post]
match 'service/:issue_id/submit', as: 'service_form_submit', to: "services#form_submit", via: [:get, :post]
match 'service/:issue_id/check-in', as: 'service_form_checkin', to: "services#checkin", via: [:get, :post]
match 'services/:id/download', as: 'service_download', to: "services#download", via: [:get]
