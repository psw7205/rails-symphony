require "test_helper"

class Symphony::RetryEntryTest < ActiveSupport::TestCase
  test "belongs to managed workflow" do
    association = Symphony::RetryEntry.reflect_on_association(:managed_workflow)

    assert_not_nil association
    assert_equal :belongs_to, association.macro
  end
end
