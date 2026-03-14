require "open3"

module Symphony
  class Workspace
    SAFE_CHARS = /[^A-Za-z0-9._-]/

    attr_reader :root

    def initialize(root:, hooks: {}, hooks_timeout_ms: 60_000)
      @root = File.expand_path(root)
      @hooks = hooks
      @hooks_timeout_ms = hooks_timeout_ms
    end

    def self.safe_identifier(identifier)
      (identifier || "issue").to_s.gsub(SAFE_CHARS, "_")
    end

    def workspace_path(identifier)
      safe_id = self.class.safe_identifier(identifier)
      File.join(@root, safe_id)
    end

    def prepare(identifier)
      path = workspace_path(identifier)
      validation = validate_path(path)
      return validation if validation[:error]

      created = false
      if Dir.exist?(path)
        clean_tmp_artifacts(path)
      elsif File.exist?(path)
        FileUtils.rm_rf(path)
        FileUtils.mkdir_p(path)
        created = true
      else
        FileUtils.mkdir_p(path)
        created = true
      end

      if created && @hooks["after_create"]
        result = run_hook(@hooks["after_create"], path, "after_create")
        if result[:error]
          FileUtils.rm_rf(path)
          return result
        end
      end

      { ok: true, path: path, created: created }
    rescue => e
      { error: :workspace_creation_failed, message: e.message }
    end

    def remove(identifier)
      path = workspace_path(identifier)
      return unless File.exist?(path)

      validation = validate_path(path)
      return if validation[:error]

      if Dir.exist?(path) && @hooks["before_remove"]
        run_hook(@hooks["before_remove"], path, "before_remove")
      end

      FileUtils.rm_rf(path)
    end

    def run_before_run_hook(identifier)
      return :ok unless @hooks["before_run"]
      path = workspace_path(identifier)
      run_hook(@hooks["before_run"], path, "before_run")
    end

    def run_after_run_hook(identifier)
      return :ok unless @hooks["after_run"]
      path = workspace_path(identifier)
      run_hook(@hooks["after_run"], path, "after_run")
      :ok
    end

    def validate_path(path)
      expanded = File.expand_path(path)
      root_prefix = File.expand_path(@root) + "/"

      if expanded == File.expand_path(@root)
        return { error: :workspace_equals_root }
      end

      unless expanded.start_with?(root_prefix)
        return { error: :workspace_outside_root }
      end

      { ok: true }
    end

    private

      def clean_tmp_artifacts(path)
        %w[tmp .elixir_ls].each do |entry|
          FileUtils.rm_rf(File.join(path, entry))
        end
      end

      def run_hook(command, workspace_path, hook_name)
        Rails.logger.info("[Symphony::Workspace] Running hook=#{hook_name} workspace=#{workspace_path}")

        result = nil

        thread = Thread.new do
          stdout, stderr, status = Open3.capture3("sh", "-lc", command, chdir: workspace_path)
          result = { stdout: stdout, stderr: stderr, status: status }
        end

        unless thread.join(@hooks_timeout_ms / 1000.0)
          thread.kill
          Rails.logger.warn("[Symphony::Workspace] Hook timed out hook=#{hook_name} timeout_ms=#{@hooks_timeout_ms}")
          return { error: :hook_timeout, hook: hook_name }
        end

        if result[:status]&.success?
          { ok: true }
        else
          Rails.logger.warn("[Symphony::Workspace] Hook failed hook=#{hook_name} status=#{result[:status]&.exitstatus}")
          { error: :hook_failed, hook: hook_name, status: result[:status]&.exitstatus }
        end
      rescue => e
        Rails.logger.error("[Symphony::Workspace] Hook error hook=#{hook_name} error=#{e.message}")
        { error: :hook_error, hook: hook_name, message: e.message }
      end
  end
end
