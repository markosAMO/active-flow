module ActiveFlow
  class ConnectionDefinition
    attr_reader :model_relation_type, :name, :options

    def initialize(model_relation_type, name, **options)
      @model_relation_type = model_relation_type.to_sym
      @name = name.to_sym
      @options = options
    end
  end
end
