module ActiveFlow
  class Configuration
    attr_accessor :auto_include

    def initialize
      @auto_include = false
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end
  end
end
