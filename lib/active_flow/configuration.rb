module ActiveFlow
  class Configuration
    attr_accessor :auto_include, :routes_namespace, :base_controller

    def initialize
      @auto_include      = false
      @routes_namespace  = "flow"
      @base_controller   = "ActionController::API"
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
