module ActiveFlow
  class ScopeDefinition
    attr_reader :name, :fields, :connections

    def initialize(name, fields: [], connections: [])
      @name        = name.to_sym
      @fields      = Array(fields).map(&:to_sym)
      @connections = Array(connections).map(&:to_sym)
    end
  end
end
