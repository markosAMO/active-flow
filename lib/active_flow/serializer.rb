# frozen_string_literal: true

module ActiveFlow
  class Serializer
    def self.serialize(subject, scope: nil)
      new(subject, scope: scope).serialize
    end

    def self.to_service_json(subject, scope: nil)
      new(subject, scope: scope).to_service_json
    end

    def self.to_schema(klass)
      new(klass).to_schema
    end

    def initialize(subject, scope: nil)
      @subject = subject
      @scope   = scope&.to_sym
    end

    # React Flow format: { nodes: [...], edges: [...] }
    def serialize
      collection? ? serialize_collection : serialize_record(@subject)
    end

    # Plain nested JSON format for services
    def to_service_json
      if collection?
        @subject.map { |record| build_service_hash(record) }
      else
        build_service_hash(@subject)
      end
    end

    # Schema format describing fields and associations with their types
    def to_schema
      klass = @subject.is_a?(Class) ? @subject : @subject.class
      node_type = klass.flow_node_type.to_sym

      schema = klass._flow_fields.each_with_object({}) do |field, hash|
        hash[field.name] = field.type || ar_column_type(klass, field.name)
      end

      klass._flow_connections.each do |connection|
        assoc_klass = klass.reflect_on_association(connection.name)&.klass
        flow_attributes = if assoc_klass&.respond_to?(:_flow_fields)
                            assoc_klass._flow_fields.each_with_object({}) do |f, h|
                              h[f.name] = f.type || ar_column_type(assoc_klass, f.name)
                            end
                          else
                            {}
                          end

        schema[connection.name] = {
          relation_type: connection.model_relation_type,
          flow_attributes: flow_attributes
        }
      end

      { node_type => schema }
    end

    private

    def resolve_fields(klass)
      return klass._flow_fields unless @scope

      scope_def = klass._flow_scopes[@scope]
      raise ArgumentError, "Scope :#{@scope} is not defined on #{klass.name}" unless scope_def

      klass._flow_fields.select { |f| scope_def.fields.include?(f.name) }
    end

    def resolve_connections(klass)
      return klass._flow_connections unless @scope

      scope_def = klass._flow_scopes[@scope]
      raise ArgumentError, "Scope :#{@scope} is not defined on #{klass.name}" unless scope_def

      return [] if scope_def.connections.empty?

      declared_names = klass._flow_connections.map(&:name)
      scope_def.connections.each do |conn_name|
        unless declared_names.include?(conn_name)
          raise ArgumentError, "Connection :#{conn_name} in scope :#{@scope} is not declared as flow_connection on #{klass.name}"
        end
      end

      klass._flow_connections.select { |c| scope_def.connections.include?(c.name) }
    end

    def collection?
      @subject.is_a?(ActiveRecord::Relation) || @subject.is_a?(Array)
    end

    def serialize_collection
      nodes = @subject.map { |record| build_node(record) }
      { nodes: nodes, edges: [] }
    end

    def serialize_record(record)
      nodes  = []
      edges  = []

      main_node = build_node(record)
      nodes << main_node

      resolve_connections(record.class).each do |connection|
        associated = record.public_send(connection.name)
        associated = [associated].compact unless associated.respond_to?(:each)

        associated.each do |assoc_record|
          assoc_node = build_node(assoc_record)
          nodes << assoc_node
          edges << build_edge(main_node[:id], assoc_node[:id], connection)
        end
      end

      { nodes: nodes, edges: edges }
    end

    def build_node(record)
      klass     = record.class
      node_type = klass.respond_to?(:flow_node_type) ? klass.flow_node_type : klass.name.underscore

      fields = klass.respond_to?(:_flow_fields) ? resolve_fields(klass) : []

      data = if fields.any?
               fields.each_with_object({ id: record.id }) do |field, hash|
                 hash[field.name] = record.public_send(field.name)
               end
             else
               { id: record.id }
             end

      { id: "#{node_type}-#{record.id}", type: node_type, data: data }
    end

    def build_edge(source_id, target_id, connection)
      {
        id: "#{source_id}__#{target_id}",
        source: source_id,
        target: target_id,
        label: connection.model_relation_type.to_s
      }
    end

    def build_service_hash(record)
      klass = record.class

      hash = resolve_fields(klass).each_with_object({ id: record.id }) do |field, h|
        h[field.name] = record.public_send(field.name)
      end

      resolve_connections(klass).each do |connection|
        associated = record.public_send(connection.name)
        plural     = %i[has_many has_and_belongs_to_many].include?(connection.model_relation_type)

        hash[connection.name] = if plural
                                  associated.map { |r| build_assoc_hash(r) }
                                else
                                  associated ? build_assoc_hash(associated) : nil
                                end
      end

      hash
    end

    def build_assoc_hash(record)
      klass = record.class
      return { id: record.id } unless klass.respond_to?(:_flow_fields) && klass._flow_fields.any?

      klass._flow_fields.each_with_object({ id: record.id }) do |field, h|
        h[field.name] = record.public_send(field.name)
      end
    end

    def ar_column_type(klass, field_name)
      klass.columns_hash[field_name.to_s]&.type || :unknown
    end
  end
end
