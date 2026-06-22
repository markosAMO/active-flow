# frozen_string_literal: true

module ActiveFlow
  module Flowable
    extend ActiveSupport::Concern

    included do
      class_attribute :_flow_fields, default: []
      class_attribute :_flow_connections, default: []
      class_attribute :_flow_scopes, default: {}
    end

    class_methods do
      def flow_field(*names, type: nil, **options)
        names.each do |name|
          self._flow_fields = _flow_fields + [FieldDefinition.new(name, type: type, **options)]
        end
      end

      def flow_connection(model_relation_type, *names, **options)
        names.each do |name|
          self._flow_connections = _flow_connections + [ConnectionDefinition.new(model_relation_type, name, **options)]
        end
      end

      # Marks all AR columns as flow_fields, optionally excluding some.
      def flow_all_attributes(except: [])
        except = Array(except).map(&:to_sym)
        column_names.map(&:to_sym).reject { |c| except.include?(c) }.each do |col|
          flow_field col
        end
      end

      def flow_scope(name, fields: [], connections: [])
        self._flow_scopes = _flow_scopes.merge(
          name.to_sym => ScopeDefinition.new(name, fields: fields, connections: connections)
        )
      end

      # Marks all AR associations as flow_connections, optionally excluding some.
      def flow_all_connections(except: [])
        except = Array(except).map(&:to_sym)
        reflect_on_all_associations.each do |reflection|
          next if except.include?(reflection.name)

          flow_connection reflection.macro, reflection.name
        end
      end

      def flow_node_type
        model_name.singular
      end
    end
  end
end
