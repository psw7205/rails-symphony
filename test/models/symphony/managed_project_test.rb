require "test_helper"

class Symphony::ManagedProjectTest < ActiveSupport::TestCase
  test "model class exists" do
    assert defined?(Symphony::ManagedProject), "expected Symphony::ManagedProject to be defined"
  end

  test "model binds to managed projects table" do
    assert_equal "symphony_managed_projects", Symphony::ManagedProject.table_name
  end

  test "has many managed workflows" do
    association = Symphony::ManagedProject.reflect_on_association(:managed_workflows)

    assert_not_nil association
    assert_equal :has_many, association.macro
  end

  test "managed projects table includes planned columns and unique slug index" do
    table_name = :symphony_managed_projects
    connection = ActiveRecord::Base.connection

    assert connection.data_source_exists?(table_name), "expected #{table_name} table to exist"

    columns = connection.columns(table_name).index_by(&:name)
    %w[name slug status description created_at updated_at].each do |column_name|
      assert_includes columns.keys, column_name
    end

    slug_index = connection.indexes(table_name).find { |index| index.columns == [ "slug" ] }
    assert slug_index&.unique, "expected unique index on slug"
  end

  test "requires name, slug, and status" do
    project = Symphony::ManagedProject.new

    assert_not project.valid?
    assert_includes project.errors[:name], "can't be blank"
    assert_includes project.errors[:slug], "can't be blank"
    assert_includes project.errors[:status], "can't be blank"
  end

  test "requires a unique slug" do
    Symphony::ManagedProject.create!(name: "Alpha", slug: "alpha", status: "active")

    project = Symphony::ManagedProject.new(name: "Beta", slug: "alpha", status: "inactive")

    assert_not project.valid?
    assert_includes project.errors[:slug], "has already been taken"
  end

  test "allows only active or inactive status" do
    active_project = Symphony::ManagedProject.new(name: "Alpha", slug: "alpha-active", status: "active")
    inactive_project = Symphony::ManagedProject.new(name: "Beta", slug: "beta-inactive", status: "inactive")
    invalid_project = Symphony::ManagedProject.new(name: "Gamma", slug: "gamma-archived", status: "archived")

    assert active_project.valid?
    assert inactive_project.valid?
    assert_not invalid_project.valid?
    assert_includes invalid_project.errors[:status], "is not included in the list"
  end
end
