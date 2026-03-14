Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Dashboard
  root "symphony/dashboard#show"

  # JSON API (SPEC 13.7.2)
  namespace :api do
    namespace :v1 do
      resource :state, only: :show
      resource :refresh, only: :create
      get ":issue_identifier", to: "issues#show", as: :issue
    end
  end
end
