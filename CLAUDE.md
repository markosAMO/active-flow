# ActiveFlow — Contexto para Claude

## Qué es

Gema Ruby que:
1. Provee un DSL (`Flowable`) para marcar campos y relaciones de modelos ActiveRecord.
2. Serializa esos modelos en formato React Flow (`{ nodes, edges }`) o JSON plano para APIs (`to_service_json`).
3. Genera controladores CRUD y rutas RESTful automáticamente para cada modelo registrado (estilo Active Admin).

## Estructura de archivos

```
lib/active_flow.rb                  # entry point: require, módulo principal, register/with/generate_controller
lib/active_flow/version.rb
lib/active_flow/configuration.rb    # Configuration (auto_include, routes_namespace, base_controller) + ActiveFlow.configure
lib/active_flow/field_definition.rb # Value object: name, type, options
lib/active_flow/connection_definition.rb # Value object: model_relation_type, name, options
lib/active_flow/scope_definition.rb # Value object: name, fields[], connections[]
lib/active_flow/flowable.rb         # ActiveSupport::Concern con el DSL (flow_field, flow_connection, flow_scope…)
lib/active_flow/serializer.rb       # Lógica de serialización: serialize, to_service_json, to_schema
lib/active_flow/resource.rb         # Resource (lazy model resolution) + ResourceRegistration (DSL de register)
lib/active_flow/resource_controller.rb # ResourceActions concern + ResourceController < ActionController::API
lib/active_flow/router.rb           # Rails.application.routes.draw { ... } — inyectado por routes_reloader
lib/active_flow/railtie.rb          # Hooks de boot de Rails
```

## Ciclo de boot de Rails (orden crítico)

1. `active_flow.extend_active_record` — incluye `Flowable` en todos los modelos AR si `auto_include: true`.
2. `active_flow.ignore_flow_dir` — le dice a Zeitwerk que ignore `app/flow/` (antes de cargarlos manualmente).
3. `active_flow.load_resources` — hace `load` de todos los `.rb` en `app/flow/` (después de `load_config_initializers`).
4. `active_flow.routes` — agrega `router.rb` al inicio de `routes_reloader.paths`; las rutas se dibujan cuando Rails finaliza el boot.

## Decisiones de diseño importantes

### String, no constante en `register`

```ruby
# CORRECTO
ActiveFlow.register "AdminUser"
ActiveFlow.register "Project" do
  scope :summary
end

# INCORRECTO — falla en boot con Rails 7 + Zeitwerk
ActiveFlow.register AdminUser
```

**Por qué:** Rails 7 no permite resolver constantes de autoload durante initializers. La constante `AdminUser` se evalúa antes de que Ruby llame a `register`, cuando Zeitwerk todavía no cargó el modelo. `Resource#model` resuelve la constante con `constantize` de forma lazy (primera request).

### `app/flow/` excluido de Zeitwerk

El Railtie hace `Rails.autoloaders.each { |l| l.ignore(flow_dir) }` antes de cargar los archivos. Si no, Zeitwerk espera que `resources.rb` defina una constante `Resources` y lanza `Zeitwerk::NameError`.

### Rutas via `routes_reloader.paths`

No se llama `app.routes.draw {}` directamente en un initializer porque eso dispara `finalize!` demasiado temprano, antes de que Devise configure Warden, causando `undefined method 'failure_app=' for nil`. En cambio, `router.rb` se inyecta en `routes_reloader.paths` y Rails lo carga en el momento correcto.

### `ResourceRegistration#scope` es getter y setter

```ruby
def scope(name = nil)
  name ? @scope = name.to_sym : @scope
end
```

`attr_reader :scope` + `def scope(name)` en la misma clase causa conflicto: el método con argumento obligatorio sobreescribe el getter. La solución es un único método con argumento opcional.

### Acciones CRUD en `ResourceActions`, no en `ResourceController` directamente

Las acciones CRUD están definidas en `ActiveFlow::ResourceActions` (un `ActiveSupport::Concern`). `ResourceController` lo incluye, pero `generate_controller` también lo incluye en cualquier clase base configurada. Esto permite que los controllers generados hereden de `ApplicationController` u otro controller del usuario sin perder las acciones CRUD.

```ruby
klass = Class.new(base)
klass.include(ResourceActions) unless klass.ancestors.include?(ResourceActions)
```

### Agrupación por controller base y namespace con `ActiveFlow.with`

```ruby
ActiveFlow.with base_controller: "Api::V1::BaseController", namespace: "api/v1" do
  register "Project"   # → /api/v1/projects
  register "Task"      # → /api/v1/tasks
end
```

`with` acepta `base_controller:` y `namespace:` de forma independiente (podés pasar uno o ambos). Usa `@current_base_controller` y `@current_namespace` con guardado/restauración en `ensure` para soportar bloques anidados. `register` dentro del bloque toma esos valores; fuera del bloque caen al default de `configuration`.

`router.rb` agrupa los recursos por namespace antes de dibujar las rutas. Excluye `new` y `edit` porque la gema apunta a APIs, no a apps que renderizan formularios HTML:

```ruby
ActiveFlow.resources
  .group_by { |_, resource| resource.namespace || ActiveFlow.configuration.routes_namespace }
  .each do |ns, pairs|
    scope path: ns, module: "active_flow" do
      pairs.each { |resource_name, _| resources resource_name, except: %i[new edit] }
    end
  end
```

### Controladores generados en el namespace `ActiveFlow::`

```ruby
ActiveFlow.const_set("ProjectsController", Class.new(base))
```

Esto permite que el usuario reabra el controller en `app/controllers/active_flow/projects_controller.rb` y agregue concerns sin modificar la gema.

### Paginado en `index`

El `index` pagina solo cuando el request incluye `page` y `page_size`. Sin esos params devuelve el array plano sin cambios.

```ruby
return render json: Serializer.to_service_json(resource_class.all, scope: flow_scope) unless params[:page].present? && params[:page_size].present?
```

Con params: ejecuta `SELECT COUNT(*)` para el total y `OFFSET/LIMIT` para la página. Respuesta:

```json
{ "data": [...], "meta": { "page": 1, "page_size": 25, "total": 80, "total_pages": 4 } }
```

`resource_class.all` es una `Relation` lazy — no carga registros en memoria hasta el `OFFSET/LIMIT`.

### Hook `flow_before_action` en el modelo

El controller llama `resource_class.flow_before_action(action_name, self)` antes de cada acción si el modelo responde al método. Es opt-in: si el modelo no lo define, se ignora.

### `flow_field` acepta métodos, no solo columnas

El serializador usa `public_send` para leer valores, por lo que `flow_field` puede declarar cualquier método del modelo — no solo columnas AR. Los métodos calculados aparecen en la respuesta pero quedan excluidos de `permitted_params` automáticamente.

`permitted_params` en `Resource` filtra por `model.column_names`:

```ruby
column_names = model.column_names.map(&:to_sym)
model._flow_fields.map(&:name).select { |f| column_names.include?(f) } - [:id]
```

### `flow_field` vs `flow_connection` para relaciones

Aunque `flow_field` acepta cualquier método, **no debe usarse para relaciones** — si se declara `flow_field :tasks`, el serializador vuelca la colección AR completa sin filtros ni DSL.

`flow_connection` en cambio usa `build_assoc_hash`, que respeta los `_flow_fields` declarados en el modelo asociado:

```ruby
def build_assoc_hash(record)
  klass = record.class
  return { id: record.id } unless klass.respond_to?(:_flow_fields) && klass._flow_fields.any?
  klass._flow_fields.each_with_object({ id: record.id }) do |field, h|
    h[field.name] = record.public_send(field.name)
  end
end
```

Esto garantiza que la serialización en cascada respete el contrato del DSL en cada modelo. `flow_connection` también puede declarar métodos que no son asociaciones AR estándar, siempre que retornen registros.

## Configuración en la app consumidora

```ruby
# config/initializers/active_flow.rb
ActiveFlow.configure do |config|
  config.auto_include     = false              # si true, todos los AR incluyen Flowable
  config.routes_namespace = "flow"             # prefijo de rutas → /flow/projects
  config.base_controller  = "ApplicationController"  # default: "ActionController::API"
end

# app/flow/resources.rb
ActiveFlow.with base_controller: "Api::V1::BaseController", namespace: "api/v1" do
  register "Project" do
    scope :summary
  end
  register "Task"
end

ActiveFlow.with base_controller: "Admin::BaseController", namespace: "admin" do
  register "AdminUser"
end
```

## Cómo correr los specs

```bash
bundle exec rspec
```

Actualmente hay un `spec/spec_helper.rb` básico. Los specs de integración están pendientes.

## Pendientes conocidos

- Specs de integración (serializer, controller, rutas).
- Documentar `resource.rb`, `resource_controller.rb`, `router.rb` y `railtie.rb` en `docs/internals.md`.
