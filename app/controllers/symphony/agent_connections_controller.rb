module Symphony
  class AgentConnectionsController < ApplicationController
    def new
      @agent_connection = AgentConnection.new(status: "active")
    end

    def create
      @agent_connection = AgentConnection.new(agent_connection_params)
      @agent_connection.config_json = raw_config_json

      if assign_parsed_config(@agent_connection) && @agent_connection.save
        redirect_to "/projects"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @agent_connection = AgentConnection.find(params[:id])
    end

    def update
      @agent_connection = AgentConnection.find(params[:id])
      @agent_connection.assign_attributes(agent_connection_params)
      @agent_connection.config_json = raw_config_json

      if assign_parsed_config(@agent_connection) && @agent_connection.save
        redirect_to "/projects"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @agent_connection = AgentConnection.find(params[:id])
      @agent_connection.destroy!
      redirect_to "/projects"
    end

    private
      def agent_connection_params
        params.require(:agent_connection).permit(:name, :kind, :status)
      end

      def raw_config_json
        params.dig(:agent_connection, :config_json).to_s
      end

      def assign_parsed_config(agent_connection)
        return agent_connection.config = {} if raw_config_json.blank?

        agent_connection.config = JSON.parse(raw_config_json)
        true
      rescue JSON::ParserError
        agent_connection.errors.add(:config_json, "is invalid JSON")
        false
      end
  end
end
