module ActiveFlow
  class FieldDefinition
    attr_reader :name, :type, :options

    def initialize(name, type: nil, **options)
      @name = name.to_sym
      @type = type
      @options = options
    end
  end
end
