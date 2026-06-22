module ActiveFlow
  class ResourceController < ActionController::API
    before_action :set_record, only: [:show, :update, :destroy]

    def index
      render json: Serializer.serialize(resource_class.all, scope: flow_scope)
    end

    def show
      render json: Serializer.serialize(@record, scope: flow_scope)
    end

    def create
      @record = resource_class.new(permitted_params)
      if @record.save
        render json: Serializer.serialize(@record, scope: flow_scope), status: :created
      else
        render json: { errors: @record.errors }, status: :unprocessable_entity
      end
    end

    def update
      if @record.update(permitted_params)
        render json: Serializer.serialize(@record, scope: flow_scope)
      else
        render json: { errors: @record.errors }, status: :unprocessable_entity
      end
    end

    def destroy
      @record.destroy
      head :no_content
    end

    private

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
end
