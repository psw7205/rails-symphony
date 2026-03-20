module Symphony
  class ProjectsController < ApplicationController
    def index
      @projects = ManagedProject.order(:name)
    end
  end
end
