module Symphony
  class TrackerConnectionsController < ApplicationController
    def new
      @tracker_connection = TrackerConnection.new(status: "active")
    end

    def create
      @tracker_connection = TrackerConnection.new(tracker_connection_params)
      @tracker_connection.config_json = raw_config_json

      if assign_parsed_config(@tracker_connection) && @tracker_connection.save
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
      @tracker_connection.config_json = raw_config_json

      if assign_parsed_config(@tracker_connection) && @tracker_connection.save
        redirect_to "/projects"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @tracker_connection = TrackerConnection.find(params[:id])
      @tracker_connection.destroy!
      redirect_to "/projects"
    end

    private
      def tracker_connection_params
        params.require(:tracker_connection).permit(:name, :kind, :status)
      end

      def raw_config_json
        params.dig(:tracker_connection, :config_json).to_s
      end

      def assign_parsed_config(tracker_connection)
        return tracker_connection.config = {} if raw_config_json.blank?

        tracker_connection.config = JSON.parse(raw_config_json)
        true
      rescue JSON::ParserError
        tracker_connection.errors.add(:config_json, "is invalid JSON")
        false
      end
  end
end
