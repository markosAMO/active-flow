module ActiveFlow
  class Resource
    attr_reader :model_name, :scope, :base_controller, :namespace, :resource_name, :controller_name

    def initialize(model_name, scope: nil, base_controller: nil, namespace: nil)
      @model_name      = model_name.to_s
      @scope           = scope
      @base_controller = base_controller
      @namespace       = namespace
      @resource_name   = @model_name.underscore.pluralize.to_sym
      @controller_name = "#{@model_name.pluralize}Controller"
    end

    def model
      @model ||= model_name.constantize
    end

    def permitted_params
      column_names = model.column_names.map(&:to_sym)
      @permitted_params ||= model._flow_fields.map(&:name).select { |f| column_names.include?(f) } - [:id]
    end
  end

  class ResourceRegistration
    def scope(name = nil)
      name ? @scope = name.to_sym : @scope
    end
  end
end
