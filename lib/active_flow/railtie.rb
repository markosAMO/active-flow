module ActiveFlow
  class Railtie < Rails::Railtie
    initializer "active_flow.extend_active_record" do
      ActiveSupport.on_load(:active_record) do
        include ActiveFlow::Flowable if ActiveFlow.configuration.auto_include
      end
    end

    initializer "active_flow.ignore_flow_dir", before: "active_flow.load_resources" do |app|
      flow_dir = app.root.join("app/flow").to_s
      Rails.autoloaders.each { |loader| loader.ignore(flow_dir) }
    end

    initializer "active_flow.load_resources", after: :load_config_initializers do |app|
      Dir[app.root.join("app/flow/**/*.rb")].sort.each { |f| load f }
    end

    initializer "active_flow.generate_controllers", after: "active_flow.load_resources" do
      config.after_initialize { ActiveFlow.generate_all_controllers }
    end

    initializer "active_flow.routes", after: "active_flow.load_resources" do |app|
      app.routes_reloader.paths.unshift(
        File.join(File.dirname(__FILE__), "router.rb")
      )
    end
  end
end
