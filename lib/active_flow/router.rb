Rails.application.routes.draw do
  ActiveFlow.resources
    .group_by { |_, resource| resource.namespace || ActiveFlow.configuration.routes_namespace }
    .each do |ns, pairs|
      scope path: ns, module: "active_flow" do
        pairs.each do |resource_name, _|
          resources resource_name, except: %i[new edit]
        end
      end
    end
end
