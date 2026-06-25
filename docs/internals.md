# ActiveFlow — Internals

Documentación técnica archivo por archivo. Se va completando en orden.

---

## `connection_definition.rb`

Value object que representa una asociación AR registrada como conexión de flujo.

```ruby
ConnectionDefinition.new(:has_many, :tasks)
# => #<ConnectionDefinition macro=:has_many, name=:tasks, options={}>
```

### Atributos

| Atributo              | Tipo   | Descripción |
|-----------------------|--------|-------------|
| `model_relation_type` | Symbol | Tipo de asociación AR: `:has_many`, `:belongs_to`, `:has_one`, `:has_and_belongs_to_many` |
| `name`                | Symbol | Nombre de la asociación tal como está definida en el modelo |
| `options`             | Hash   | Opciones adicionales — actualmente sin uso, reservado |

### Rol en la gema

El `Serializer` consume este objeto en dos lugares:

- **`build_edge`** — usa `model_relation_type` como `label` del edge React Flow (`"has_many"`)
- **`to_schema`** — usa `model_relation_type` como `relation_type` y `name` para reflejar la clase asociada y sus campos

### Usos potenciales de `options`

`options` hoy está vacío pero su posición en la firma (`**options`) lo deja abierto. Casos que tendría sentido implementar:

| Opción            | Tipo             | Uso potencial |
|-------------------|------------------|---------------|
| `label:`          | String           | Sobreescribir el label del edge en lugar de usar el macro (`"depends on"` en vez de `"has_many"`) |
| `type:`           | String           | Tipo de edge React Flow: `"default"`, `"straight"`, `"step"`, `"smoothstep"` |
| `animated:`       | Boolean          | Pasar `animated: true` al edge para mostrarlo con animación en React Flow |
| `style:`          | Hash             | CSS inline para el edge (`{ stroke: "#ff0000" }`) |
| `marker_end:`     | String / Hash    | Tipo de punta de flecha React Flow (`"arrow"`, `"arrowclosed"`) |
| `source_handle:`  | String           | Handle de origen en el nodo fuente (útil con layouts custom) |
| `target_handle:`  | String           | Handle de destino en el nodo objetivo |
| `filter:`         | Proc / Lambda    | Filtrar qué registros asociados se incluyen en la serialización |
| `through:`        | Symbol           | Indicar el join model explícito para `has_many :through` |

El más inmediato de implementar sería `label:`, `type:` y `animated:` porque son propiedades directas del objeto edge de React Flow y no requieren lógica adicional en el serializador — solo pasarlos al hash de `build_edge`.

---

## `field_definition.rb`

Value object que representa un atributo del modelo registrado como campo de flujo.

```ruby
FieldDefinition.new(:title)
FieldDefinition.new(:priority, type: :integer)
```

### Atributos

| Atributo  | Tipo    | Descripción |
|-----------|---------|-------------|
| `name`    | Symbol  | Nombre del atributo del modelo |
| `type`    | Symbol? | Tipo explícito del campo. `nil` si no se declaró — el `Serializer` lo infiere desde `columns_hash` de AR |
| `options` | Hash    | Opciones adicionales — actualmente sin uso, reservado |

### Rol en la gema

El `Serializer` lo usa en dos lugares:

- **`build_node`** — itera `_flow_fields` para construir el hash `data` de cada nodo con los valores del registro
- **`to_schema`** — resuelve el tipo via `field.type || ar_column_type(klass, field.name)` para describir la forma del modelo

### Resolución de tipo

```
type explícito en flow_field  →  columna en AR columns_hash  →  :unknown
```

### Usos potenciales de `options`

| Opción       | Tipo    | Uso potencial |
|--------------|---------|---------------|
| `serialize:` | Proc    | Transformación custom del valor antes de incluirlo en el nodo (e.g. formatear fechas) |
| `hidden:`    | Boolean | Excluir el campo del output de `serialize` pero mantenerlo en `to_schema` |
| `label:`     | String  | Alias del campo en el JSON de salida sin renombrar el atributo en el modelo |
| `readonly:`  | Boolean | Hint para el frontend de que el campo no es editable |

---

## `scope_definition.rb`

Value object que representa un scope nombrado — una agrupación de campos y conexiones ya declarados como flow.

```ruby
ScopeDefinition.new(:summary, fields: [:id, :name], connections: [:tasks])
```

### Atributos

| Atributo      | Tipo          | Descripción |
|---------------|---------------|-------------|
| `name`        | Symbol        | Nombre del scope |
| `fields`      | Array<Symbol> | Nombres de los `flow_field` incluidos en el scope |
| `connections` | Array<Symbol> | Nombres de los `flow_connection` incluidos en el scope |

Ambos arrays son opcionales — default `[]`. Un scope sin `connections` no serializa ninguna relación. Un scope sin `fields` no incluye ningún atributo en `data`.

### Rol en la gema

El `Serializer` lo consume a través de `resolve_fields` y `resolve_connections`:

- **`resolve_fields`** — filtra `_flow_fields` del modelo dejando solo los que están en `scope_def.fields`
- **`resolve_connections`** — valida que cada nombre en `scope_def.connections` esté declarado como `flow_connection` y filtra `_flow_connections` en consecuencia

---

## `flowable.rb`

`ActiveSupport::Concern` que expone el DSL completo. Al incluirlo en un modelo AR, habilita todos los métodos de clase para declarar el contrato de serialización del modelo.

```ruby
class Project < ApplicationRecord
  include ActiveFlow::Flowable
end
```

### Estado de clase

Al incluir el concern se inicializan tres `class_attribute` independientes por modelo:

| Atributo            | Tipo                            | Contenido |
|---------------------|---------------------------------|-----------|
| `_flow_fields`      | `Array<FieldDefinition>`        | Campos registrados con `flow_field` |
| `_flow_connections` | `Array<ConnectionDefinition>`   | Asociaciones registradas con `flow_connection` |
| `_flow_scopes`      | `Hash<Symbol, ScopeDefinition>` | Scopes registrados con `flow_scope` |

`class_attribute` de Rails garantiza que cada modelo tenga su propia copia — no comparten estado entre sí.

### Métodos de clase

#### `flow_field(*names, type: nil, **options)`

Registra uno o más atributos del modelo. Por cada nombre crea un `FieldDefinition` y lo agrega a `_flow_fields`.

```ruby
flow_field :name, :status
flow_field :priority, type: :integer
```

#### `flow_connection(model_relation_type, *names, **options)`

Registra una o más asociaciones AR. Por cada nombre crea un `ConnectionDefinition` y lo agrega a `_flow_connections`.

```ruby
flow_connection :has_many,   :tasks
flow_connection :belongs_to, :owner
```

#### `flow_all_attributes(except: [])`

Atajo que llama `flow_field` sobre todas las columnas de la tabla leyéndolas desde `column_names` de AR. El parámetro `except:` filtra las que no se quieren exponer.

```ruby
flow_all_attributes except: [:created_at, :updated_at]
```

#### `flow_scope(name, fields: [], connections: [])`

Define un scope nombrado — una vista parcial del modelo. Crea un `ScopeDefinition` y lo guarda en `_flow_scopes` bajo la clave `name`.

```ruby
flow_scope :summary,  fields: [:id, :name, :status]
flow_scope :detailed, fields: [:id, :name, :status, :priority], connections: [:tasks]
```

#### `flow_all_connections(except: [])`

Atajo que llama `flow_connection` sobre todas las asociaciones del modelo leyéndolas desde `reflect_on_all_associations` de AR. Usa `reflection.macro` — el método de AR sobre el objeto reflection, no el nuestro.

```ruby
flow_all_connections except: [:audits]
```

#### `flow_node_type`

Devuelve el nombre singular del modelo. Lo usa el `Serializer` como campo `type` de cada nodo y como clave en `to_schema` y `to_service_json`.

```ruby
Project.flow_node_type  # => "project"
```

---

## `serializer.rb`

Transforma registros flowables en distintos formatos JSON. No tiene estado persistente — cada llamada instancia un nuevo objeto con el subject y el scope.

### Entry points (métodos de clase)

Wrappers que instancian el serializador y delegan al método de instancia correspondiente.

| Método | Firma | Descripción |
|--------|-------|-------------|
| `serialize` | `(subject, scope: nil)` | Formato React Flow: `{ nodes, edges }` |
| `to_service_json` | `(subject, scope: nil)` | Formato plano anidado para APIs |
| `to_schema` | `(klass)` | Mapa de tipos del modelo, sin datos de instancia |

`subject` puede ser un registro individual, un `ActiveRecord::Relation` o un `Array`.

### Métodos privados

#### `resolve_fields(klass)`

Decide qué `FieldDefinition` usar según el scope activo:
- Sin scope → todos los `_flow_fields` del modelo
- Con scope → filtra por los nombres en `scope_def.fields`
- Scope inexistente → lanza `ArgumentError`

#### `resolve_connections(klass)`

Decide qué `ConnectionDefinition` usar según el scope activo:
- Sin scope → todas las `_flow_connections` del modelo
- Con scope sin connections → retorna `[]`
- Con scope con connections → valida que cada una esté declarada como `flow_connection`, lanza `ArgumentError` si no, y filtra
- Scope inexistente → lanza `ArgumentError`

#### `serialize_record(record)`

Construye el output React Flow para un registro individual:
1. Crea el nodo principal con `build_node`
2. Itera `resolve_connections` del modelo
3. Para cada asociación normaliza a array (maneja `belongs_to`/`has_one` que devuelven objeto o `nil`)
4. Por cada registro asociado crea un nodo y un edge desde el nodo principal

Solo va **un nivel de profundidad** — no recursa en los registros asociados.

#### `build_node(record)`

Construye el hash de nodo React Flow:

```ruby
{ id: "project-1", type: "project", data: { id: 1, name: "Alpha" } }
```

- `id` — `"<node_type>-<record.id>"`
- `type` — `flow_node_type` del modelo, con fallback a `klass.name.underscore` si no incluye Flowable
- `data` — resultado de iterar `resolve_fields` y llamar `public_send` por cada campo

#### `build_edge(source_id, target_id, connection)`

Construye el hash de edge React Flow:

```ruby
{ id: "project-1__task-10", source: "project-1", target: "task-10", label: "has_many" }
```

El `label` viene de `connection.model_relation_type`.

#### `build_service_hash(record)`

Construye el hash anidado para `to_service_json`. Usa `resolve_fields` para los atributos y `resolve_connections` para las relaciones. Las relaciones plurales (`:has_many`, `:has_and_belongs_to_many`) se mapean a array, las singulares a un hash o `nil`.

#### `build_assoc_hash(record)`

Serializa un registro asociado usando solo sus `_flow_fields`. Si el modelo no incluye Flowable o no tiene fields declarados, devuelve `{ id: record.id }`.

#### `ar_column_type(klass, field_name)`

Infiere el tipo de un campo desde `columns_hash` de AR. Fallback a `:unknown`.

---

## `router.rb`

Dibuja las rutas RESTful para cada recurso registrado. Se inyecta en `routes_reloader.paths` desde el Railtie (ver decisión de diseño en CLAUDE.md).

### Lógica de agrupación

Los recursos se agrupan por namespace antes de dibujar las rutas, de modo que todos los recursos del mismo namespace queden bajo un solo `scope`:

```ruby
ActiveFlow.resources
  .group_by { |_, resource| resource.namespace || ActiveFlow.configuration.routes_namespace }
  .each do |ns, pairs|
    scope path: ns, module: "active_flow" do
      pairs.each { |resource_name, _| resources resource_name, except: %i[new edit] }
    end
  end
```

`new` y `edit` se excluyen porque devuelven formularios HTML — no tienen sentido en una API.

### Rutas generadas

Para un recurso registrado sin `with`, usa el `routes_namespace` del singleton de configuración (default `"flow"`):

```ruby
# app/flow/resources.rb
ActiveFlow.register :project

# Rutas generadas:
# GET    /flow/projects       → ActiveFlow::ProjectsController#index
# POST   /flow/projects       → ActiveFlow::ProjectsController#create
# GET    /flow/projects/:id   → ActiveFlow::ProjectsController#show
# PATCH  /flow/projects/:id   → ActiveFlow::ProjectsController#update
# PUT    /flow/projects/:id   → ActiveFlow::ProjectsController#update
# DELETE /flow/projects/:id   → ActiveFlow::ProjectsController#destroy
```

### Configuración con `ActiveFlow.with`

`with` permite sobreescribir namespace y controller base por grupo de recursos:

```ruby
# app/flow/resources.rb

# Bajo /admin_api/v1, heredando autenticación del AdminBaseController
ActiveFlow.with base_controller: "AdminApi::AdminBaseController", namespace: "admin_api/v1" do
  register :admin_user
  register :case_config
end

# Bajo /api/v1, con otro controller base
ActiveFlow.with base_controller: "Api::V1::BaseController", namespace: "api/v1" do
  register :project
end
```

Resultado para el primer bloque:
```
GET    /admin_api/v1/admin_users       → ActiveFlow::AdminUsersController#index
POST   /admin_api/v1/admin_users       → ActiveFlow::AdminUsersController#create
GET    /admin_api/v1/admin_users/:id   → ActiveFlow::AdminUsersController#show
...
```

`ActiveFlow::AdminUsersController` hereda de `AdminApi::AdminBaseController`, por lo que pasa por todos sus `before_action` (autenticación, validación de utility, etc.).

### Namespace vs base_controller

Son independientes — podés pasarlos juntos o por separado:

```ruby
# Solo namespace distinto, controller base del default de configuración
ActiveFlow.with namespace: "internal/v1" do
  register :audit_log
end

# Solo controller base distinto, namespace del default de configuración
ActiveFlow.with base_controller: "PublicController" do
  register :status
end
```

---

## `configuration.rb`

Objeto de configuración global de la gema con patrón singleton.

```ruby
ActiveFlow.configure do |config|
  config.auto_include = true
end
```

| Atributo            | Default                  | Descripción |
|---------------------|--------------------------|-------------|
| `auto_include`      | `false`                  | Si es `true`, todos los modelos AR incluyen `Flowable` al cargar Rails |
| `routes_namespace`  | `"flow"`                 | Prefijo de ruta para recursos registrados sin `namespace` explícito |
| `base_controller`   | `"ActionController::API"`| Controller base para recursos registrados sin `base_controller` explícito |

`ActiveFlow.configuration` devuelve la instancia singleton con lazy init. `ActiveFlow.configure` es el bloque estándar que la expone.

---

## `railtie.rb`

Conecta la gema con el ciclo de boot de Rails. Registra un `initializer` que espera a que ActiveRecord esté completamente cargado (`on_load(:active_record)`) para hacer el `include` de `Flowable` en `ActiveRecord::Base` — pero solo si `auto_include` está activado.

La condición `if auto_include` hace que por defecto la gema no toque ningún modelo. El include automático es opt-in explícito.

---

## `active_flow.rb`

Punto de entrada de la gema. Carga todas las dependencias en orden:

```
active_support          → concern, class_attribute, underscore
version                 → constante VERSION
configuration           → singleton de configuración
field_definition        → value object de campos
connection_definition   → value object de conexiones
scope_definition        → value object de scopes
flowable                → concern DSL
serializer              → motor de serialización
railtie                 → integración Rails (solo si Rails está definido)
```

El `if defined?(Rails)` al final garantiza que la gema funcione también fuera de Rails.

---
