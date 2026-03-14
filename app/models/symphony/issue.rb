module Symphony
  class Issue
    attr_reader :id, :identifier, :title, :description, :priority, :state,
                :branch_name, :url, :labels, :blocked_by, :created_at, :updated_at

    def initialize(id:, identifier:, title:, state:, description: nil, priority: nil,
                   branch_name: nil, url: nil, labels: [], blocked_by: [], created_at: nil, updated_at: nil)
      @id = id
      @identifier = identifier
      @title = title
      @description = description
      @priority = priority
      @state = state
      @branch_name = branch_name
      @url = url
      @labels = labels
      @blocked_by = blocked_by
      @created_at = created_at
      @updated_at = updated_at
    end

    def has_non_terminal_blockers?(terminal_states)
      normalized_terminal = terminal_states.map { |s| s.to_s.strip.downcase }
      blocked_by.any? do |blocker|
        blocker_state = blocker["state"].to_s.strip.downcase
        !normalized_terminal.include?(blocker_state)
      end
    end
  end
end
