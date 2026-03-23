namespace :symphony do
  desc "Import a legacy WORKFLOW.md into managed admin records"
  task :import_workflow, [ :workflow_path, :project_name, :workflow_name ] => :environment do |_task, args|
    workflow = Symphony::WorkflowImporter.import!(
      workflow_path: args[:workflow_path],
      project_name: args[:project_name],
      workflow_name: args[:workflow_name]
    )

    puts "Imported managed workflow ##{workflow.id} (project=#{workflow.managed_project.slug} workflow=#{workflow.slug})"
  end
end
