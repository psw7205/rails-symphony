module Symphony
  class RetryScheduler
    CONTINUATION_DELAY_MS = 1_000

    def self.continuation_delay_ms
      CONTINUATION_DELAY_MS
    end

    def self.failure_backoff_ms(attempt, max_backoff_ms: 300_000)
      base = 10_000 * (2**(attempt - 1))
      [ base, max_backoff_ms ].min
    end
  end
end
