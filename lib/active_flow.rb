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
require "active_flow/routing"
require "active_flow/railtie" if defined?(Rails)

module ActiveFlow
  class << self
    def resources
      @resources ||= {}
    end

    def register(model, &block)
      registration = ResourceRegistration.new
      registration.instance_eval(&block) if block_given?
      resource = Resource.new(model, scope: registration.scope)
      resources[resource.resource_name] = resource
      generate_controller(resource)
    end

    private

    def generate_controller(resource)
      return if ActiveFlow.const_defined?(resource.controller_name)

      klass = Class.new(ResourceController)
      klass.instance_variable_set(:@flow_resource, resource)
      klass.define_singleton_method(:flow_resource) { @flow_resource }
      ActiveFlow.const_set(resource.controller_name, klass)
    end
  end
end
