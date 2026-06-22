module ActiveFlow
  class Resource
    attr_reader :model, :scope, :permitted_params, :resource_name, :controller_name

    def initialize(model, scope: nil)
      @model            = model
      @scope            = scope
      @resource_name    = model.name.underscore.pluralize.to_sym
      @controller_name  = "#{model.name.pluralize}Controller"
      @permitted_params = model._flow_fields.map(&:name) - [:id]
    end
  end

  class ResourceRegistration
    attr_reader :scope

    def scope(name)
      @scope = name.to_sym
    end
  end
end
