module Symphony
  class AgentConnectionsController < ApplicationController
    def new
      @agent_connection = AgentConnection.new(status: "active")
    end

    def create
      @agent_connection = AgentConnection.new(agent_connection_params)
      @agent_connection.config = parsed_config

      if @agent_connection.save
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
      @agent_connection.config = parsed_config

      if @agent_connection.save
        redirect_to "/projects"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private
      def agent_connection_params
        params.require(:agent_connection).permit(:name, :kind, :status)
      end

      def parsed_config
        raw = params.dig(:agent_connection, :config_json)
        return {} if raw.blank?

        JSON.parse(raw)
      rescue JSON::ParserError
        {}
      end
  end
end
