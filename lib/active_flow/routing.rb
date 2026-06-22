module ActiveFlow
  module Routing
    def active_flow_routes(path: "flow")
      scope path: path, module: "active_flow" do
        ActiveFlow.resources.each_key do |resource_name|
          resources resource_name
        end
      end
    end
  end
end
