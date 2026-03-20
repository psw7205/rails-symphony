module Symphony
  class DashboardController < ApplicationController
    def show
      @console_snapshot = ::Symphony::ConsoleSnapshot.build
    end
  end
end
