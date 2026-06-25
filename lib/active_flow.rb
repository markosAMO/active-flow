require "active_support"
require "active_support/concern"
require "active_support/core_ext/class/attribute"

require "active_flow/version"
require "active_flow/configuration"
require "active_flow/field_definition"
require "active_flow/connection_definition"
require "active_flow/scope_definition"
require "active_flow/flowable"
require "active_flow/serializer"
require "active_flow/resource"
require "active_flow/resource_controller"
require "active_flow/railtie" if defined?(Rails)

module ActiveFlow
  class << self
    def resources
      @resources ||= {}
    end

    def with(base_controller: nil, namespace: nil, &block)
      previous_controller = @current_base_controller
      previous_namespace  = @current_namespace
      @current_base_controller = base_controller if base_controller
      @current_namespace       = namespace       if namespace
      instance_eval(&block)
    ensure
      @current_base_controller = previous_controller
      @current_namespace       = previous_namespace
    end

    def register(model_or_name, &block)
      registration = ResourceRegistration.new
      registration.instance_eval(&block) if block_given?
      model_name = case model_or_name
                   when Class  then model_or_name.name
                   when Symbol then model_or_name.to_s.camelize
                   when String then model_or_name.camelize
                   end
      resource = Resource.new(
        model_name,
        scope:           registration.scope,
        base_controller: @current_base_controller,
        namespace:       @current_namespace
      )
      resources[resource.resource_name] = resource
    end

    def generate_all_controllers
      resources.each_value { |resource| generate_controller(resource) }
    end

    private

    def generate_controller(resource)
      return if ActiveFlow.const_defined?(resource.controller_name)

      base_name = resource.base_controller || configuration.base_controller
      base = base_name.constantize

      klass = Class.new(base)
      klass.include(ResourceActions) unless klass.ancestors.include?(ResourceActions)
      klass.instance_variable_set(:@flow_resource, resource)
      klass.define_singleton_method(:flow_resource) { @flow_resource }
      ActiveFlow.const_set(resource.controller_name, klass)
    end
  end
end
