module Symphony
  module Logger
    def self.with_issue(issue, &block)
      tags = ["issue_id=#{issue.id || 'n/a'}", "issue_identifier=#{issue.identifier || 'n/a'}"]
      Rails.logger.tagged(*tags, &block)
    end

    def self.with_session(session_id, &block)
      Rails.logger.tagged("session_id=#{session_id}", &block)
    end
  end
end
