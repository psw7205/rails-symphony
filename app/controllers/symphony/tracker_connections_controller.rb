module Symphony
  class TrackerConnectionsController < ApplicationController
    def new
      @tracker_connection = TrackerConnection.new(status: "active")
    end

    def create
      @tracker_connection = TrackerConnection.new(tracker_connection_params)
      @tracker_connection.config = parsed_config

      if @tracker_connection.save
        redirect_to "/projects"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @tracker_connection = TrackerConnection.find(params[:id])
    end

    def update
      @tracker_connection = TrackerConnection.find(params[:id])
      @tracker_connection.assign_attributes(tracker_connection_params)
      @tracker_connection.config = parsed_config

      if @tracker_connection.save
        redirect_to "/projects"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private
      def tracker_connection_params
        params.require(:tracker_connection).permit(:name, :kind, :status)
      end

      def parsed_config
        raw = params.dig(:tracker_connection, :config_json)
        return {} if raw.blank?

        JSON.parse(raw)
      rescue JSON::ParserError
        {}
      end
  end
end
