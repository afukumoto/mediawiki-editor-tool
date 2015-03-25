require 'fileutils'
require 'prettyprint' if $DEBUG

module MediawikiEditorTool
  class Config < Hash
    class << self
      def load
        @@instance = Config.new {|h,k| raise "Unknown key #{k}"}.load
        pp @@instance if $DEBUG
      end

      def save
        @@instance.save
      end

      def path
        File.join(MET_DIR, CONFIG_FILE_NAME)
      end

      def [](key)
        puts "Config[#{key}]: #{@@instance[key]}" if $DEBUG
        @@instance[key]
      end
    end

    def initialize
      super
      update(CONFIG_DEFAULT)
      pp self if $DEBUG
    end

    def load
      path = Config.path
      FileUtils.mkdir_p MET_DIR
      begin
        File.open(path) { |file|
          self.update(JSON.parse(file.read))
        }
      rescue
      end
      self
    end

    def save
      path = Config.path
      FileUtils.mkdir_p MET_DIR
      File.open(path, "w") { |file|
        file.write(JSON.generate(self))
      }
    end
  end
end
