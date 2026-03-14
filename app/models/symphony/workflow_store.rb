require "zlib"

module Symphony
  class WorkflowStore
    attr_reader :config, :prompt_template, :path

    def initialize(path)
      @path = path
      @stamp = nil
      @config = {}
      @prompt_template = ""
      @mutex = Mutex.new
      load!
    end

    def service_config
      ServiceConfig.new(@config)
    end

    def reload_if_changed!
      @mutex.synchronize do
        current_stamp = compute_stamp
        if current_stamp != @stamp
          do_reload(current_stamp)
        end
      end
    end

    def force_reload!
      @mutex.synchronize do
        do_reload(compute_stamp)
      end
    end

    private

      def load!
        @mutex.synchronize do
          do_reload(compute_stamp)
        end
      end

      def do_reload(stamp)
        result = Workflow.load(@path)
        if result[:error]
          Rails.logger.error("[Symphony::WorkflowStore] Reload failed: #{result[:error]} #{result[:message]}")
          return
        end
        @config = result[:config]
        @prompt_template = result[:prompt_template]
        @stamp = stamp
        Rails.logger.info("[Symphony::WorkflowStore] Workflow reloaded from #{@path}")
      end

      def compute_stamp
        return nil unless File.exist?(@path)
        stat = File.stat(@path)
        content_hash = Zlib.crc32(File.read(@path))
        [stat.mtime, stat.size, content_hash]
      rescue => e
        Rails.logger.warn("[Symphony::WorkflowStore] Stamp computation failed: #{e.message}")
        nil
      end
  end
end
