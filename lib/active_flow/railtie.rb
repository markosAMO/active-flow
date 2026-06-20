module ActiveFlow
  class Railtie < Rails::Railtie
    initializer "active_flow.extend_active_record" do
      ActiveSupport.on_load(:active_record) do
        include ActiveFlow::Flowable if ActiveFlow.configuration.auto_include
      end
    end
  end
end
