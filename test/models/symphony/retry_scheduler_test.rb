require "test_helper"

class Symphony::RetrySchedulerTest < ActiveSupport::TestCase
  test "continuation delay is 1 second" do
    assert_equal 1_000, Symphony::RetryScheduler.continuation_delay_ms
  end

  test "failure backoff is exponential" do
    assert_equal 10_000, Symphony::RetryScheduler.failure_backoff_ms(1)
    assert_equal 20_000, Symphony::RetryScheduler.failure_backoff_ms(2)
    assert_equal 40_000, Symphony::RetryScheduler.failure_backoff_ms(3)
    assert_equal 80_000, Symphony::RetryScheduler.failure_backoff_ms(4)
  end

  test "failure backoff is capped at max" do
    assert_equal 300_000, Symphony::RetryScheduler.failure_backoff_ms(10)
    assert_equal 60_000, Symphony::RetryScheduler.failure_backoff_ms(10, max_backoff_ms: 60_000)
  end
end
