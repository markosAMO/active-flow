module ActiveFlow
  module ResourceActions
    extend ActiveSupport::Concern

    included do
      before_action :run_flow_hook
      before_action :set_record, only: [:show, :update, :destroy]
    end

    def index
      render json: Serializer.to_service_json(resource_class.all, scope: flow_scope)
    end

    def show
      render json: Serializer.to_service_json(@record, scope: flow_scope)
    end

    def create
      @record = resource_class.new(permitted_params)
      if @record.save
        render json: Serializer.to_service_json(@record, scope: flow_scope), status: :created
      else
        render json: { errors: @record.errors }, status: :unprocessable_entity
      end
    end

    def update
      if @record.update(permitted_params)
        render json: Serializer.to_service_json(@record, scope: flow_scope)
      else
        render json: { errors: @record.errors }, status: :unprocessable_entity
      end
    end

    def destroy
      @record.destroy
      head :no_content
    end

    private

    def run_flow_hook
      return unless resource_class.respond_to?(:flow_before_action)
      resource_class.flow_before_action(action_name.to_sym, self)
    end

    def set_record
      @record = resource_class.find(params[:id])
    end

    def resource_class
      self.class.flow_resource.model
    end

    def flow_scope
      self.class.flow_resource.scope
    end

    def permitted_params
      params.require(resource_class.model_name.param_key.to_sym)
            .permit(self.class.flow_resource.permitted_params)
    end
  end

  class ResourceController < ActionController::API
    include ResourceActions
  end
end
