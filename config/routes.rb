Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Dashboard
  root "symphony/dashboard#show"
  get "projects", to: "symphony/projects#index"
  get "projects/new", to: "symphony/projects#new"
  post "projects", to: "symphony/projects#create"
  get "projects/:id/edit", to: "symphony/projects#edit"
  patch "projects/:id", to: "symphony/projects#update"
  get "projects/:id", to: "symphony/projects#show"
  get "agent_connections/new", to: "symphony/agent_connections#new"
  post "agent_connections", to: "symphony/agent_connections#create"
  get "tracker_connections/new", to: "symphony/tracker_connections#new"
  post "tracker_connections", to: "symphony/tracker_connections#create"
  get "workflows/new", to: "symphony/workflows#new"
  post "workflows", to: "symphony/workflows#create"
  get "workflows/:id/edit", to: "symphony/workflows#edit"
  patch "workflows/:id", to: "symphony/workflows#update"
  get "workflows/:id", to: "symphony/workflows#show"

  # JSON API (SPEC 13.7.2)
  namespace :api do
    namespace :v1 do
      resource :state, only: :show
      resource :refresh, only: :create
      get ":issue_identifier", to: "issues#show", as: :issue
      get "workflows/:workflow_id/state", to: "states#show_workflow", as: :workflow_state
      post "workflows/:workflow_id/refresh", to: "refreshes#create_workflow", as: :workflow_refresh
      get "workflows/:workflow_id/issues/:issue_identifier", to: "issues#show_workflow", as: :workflow_issue
    end
  end
end
