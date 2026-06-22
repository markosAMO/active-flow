module ActiveFlow
  class Railtie < Rails::Railtie
    initializer "active_flow.extend_active_record" do
      ActiveSupport.on_load(:active_record) do
        include ActiveFlow::Flowable if ActiveFlow.configuration.auto_include
      end
    end

    initializer "active_flow.load_resources", after: :load_config_initializers do |app|
      Dir[app.root.join("app/flow/**/*.rb")].sort.each { |f| load f }
    end

    initializer "active_flow.routing" do
      ActionDispatch::Routing::Mapper.include(ActiveFlow::Routing)
    end
  end
end
