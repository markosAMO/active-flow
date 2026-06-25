# ActiveFlow

ActiveFlow es una gema Ruby que proporciona un DSL para marcar modelos ActiveRecord como **"flowables"** y serializarlos en formatos JSON compatibles con [React Flow](https://reactflow.dev/), además de un formato plano para servicios/APIs.

## Índice

- [Instalación](#instalación)
- [Configuración](#configuración)
- [Registro de recursos](#registro-de-recursos)
- [Módulo Flowable](#módulo-flowable)
  - [flow_field](#flow_field)
  - [flow_connection](#flow_connection)
  - [flow_all_attributes](#flow_all_attributes)
  - [flow_all_connections](#flow_all_connections)
  - [Helpers de clase](#helpers-de-clase)
- [Serializador](#serializador)
  - [serialize — formato React Flow](#serialize--formato-react-flow)
  - [to_service_json — formato plano para servicios](#to_service_json--formato-plano-para-servicios)
  - [to_schema — esquema de tipos](#to_schema--esquema-de-tipos)
- [Clases internas](#clases-internas)
- [Ejemplo completo](#ejemplo-completo)

---

## Instalación

Agrega la gema a tu `Gemfile`:

```ruby
gem "active_flow"
```

Luego ejecuta:

```bash
bundle install
```

---

## Configuración

Crea un initializer en `config/initializers/active_flow.rb`:

```ruby
ActiveFlow.configure do |config|
  # Si se activa, todos los modelos ActiveRecord incluyen Flowable automáticamente.
  # Por defecto es false: debes incluir el módulo manualmente en cada modelo.
  config.auto_include = false
end
```

| Opción              | Tipo    | Default                  | Descripción |
|---------------------|---------|--------------------------|-------------|
| `auto_include`      | Boolean | `false`                  | Incluye `ActiveFlow::Flowable` en **todos** los modelos AR al cargar Rails. |
| `routes_namespace`  | String  | `"flow"`                 | Namespace bajo el cual se montan las rutas generadas automáticamente. |
| `base_controller`   | String  | `"ActionController::API"` | Clase base de la que heredan todos los controllers generados. |

---

## Registro de recursos

ActiveFlow puede generar controladores CRUD automáticamente para cualquier modelo anotado con `Flowable`, de forma similar a Active Admin.

> **Nota:** los cambios en el DSL del modelo (`flow_field`, `flow_connection`, `flow_scope`) requieren reiniciar el servidor para ser tomados. Esto ocurre porque `ActiveFlow.resources` se construye al momento del boot y memoiza el modelo. Active Admin tiene el mismo comportamiento.

### Setup

Creá los archivos de registro en `app/flow/`. Podés tener un archivo por modelo o uno solo con todos los registros:

```ruby
# app/flow/resources.rb  ← archivo único recomendado
ActiveFlow.register "Project" do
  scope :summary  # scope por defecto para serializar, opcional
end

ActiveFlow.register "AdminUser"
ActiveFlow.register "Task"
```

> **Importante:** pasá el nombre del modelo como **String** (o Symbol), nunca como constante directa.
> Rails 7 con Zeitwerk no permite resolver constantes de modelos durante los initializers de boot.
> La gema resuelve la constante con `constantize` de forma lazy, cuando llega la primera request.

La gema registra `app/flow/` como zona ignorada por Zeitwerk — no necesitás ninguna configuración extra.

### Agrupación por controller base y namespace

Usá `ActiveFlow.with` para registrar varios modelos bajo un mismo controller base y/o namespace de rutas. Podés pasar uno, el otro, o ambos:

```ruby
# app/flow/resources.rb
ActiveFlow.with base_controller: "Api::V1::BaseController", namespace: "api/v1" do
  register "Project"   # → /api/v1/projects
  register "Task"      # → /api/v1/tasks
end

ActiveFlow.with base_controller: "Admin::BaseController", namespace: "admin" do
  register "AdminUser" # → /admin/admin_users
end

# sin grupo → usa los defaults de configuration
register "PublicReport"  # → /flow/public_reports
```

Los defaults globales se configuran en el initializer:

```ruby
# config/initializers/active_flow.rb
ActiveFlow.configure do |config|
  config.routes_namespace = "flow"             # default para recursos sin namespace explícito
  config.base_controller  = "ApplicationController"  # default para recursos sin base_controller explícito
end
```

Las rutas se generan **automáticamente** al bootear — no necesitás tocar `routes.rb`.

### Rutas generadas

Para cada modelo registrado se generan las rutas RESTful estándar bajo su namespace, **excepto `new` y `edit`** (que sirven para renderizar formularios HTML — no tienen sentido en una API):

```
GET    /api/v1/projects          → index
POST   /api/v1/projects          → create
GET    /api/v1/projects/:id      → show
PATCH  /api/v1/projects/:id      → update
PUT    /api/v1/projects/:id      → update
DELETE /api/v1/projects/:id      → destroy
```

### Respuestas JSON

| Acción    | Formato de respuesta |
|-----------|----------------------|
| `index`   | array de objetos JSON planos (o paginado, ver abajo) |
| `show`    | objeto JSON plano con relaciones anidadas |
| `create`  | registro creado serializado, status `201` |
| `update`  | registro actualizado serializado, status `200` |
| `destroy` | sin body, status `204` |

Todos usan `to_service_json` — formato plano anidado, no React Flow.

En caso de error de validación (`create` / `update`):

```json
{ "errors": { "name": ["can't be blank"] } }
```

### Paginado

El `index` soporta paginado opcional. Si el request incluye los params `page` y `page_size`, la respuesta cambia de formato:

```
GET /api/v1/projects?page=1&page_size=25
```

```json
{
  "data": [
    { "id": 1, "name": "Alpha" },
    { "id": 2, "name": "Beta" }
  ],
  "meta": {
    "page": 1,
    "page_size": 25,
    "total": 80,
    "total_pages": 4
  }
}
```

Si ninguno de los dos params está presente, el `index` devuelve el array plano sin wrapper — comportamiento por defecto sin cambios.

### Permitted params

Los parámetros permitidos se derivan automáticamente de los `flow_field` declarados en el modelo, **filtrando solo los que corresponden a columnas reales de la base de datos** y excluyendo `:id`. Los params deben llegar anidados bajo la clave del modelo:

```json
{ "project": { "name": "Alpha", "status": "active" } }
```

Esto significa que podés declarar métodos calculados en `flow_field` sin riesgo — aparecen en la respuesta pero nunca en el whitelist de escritura:

```ruby
class Project < ApplicationRecord
  include ActiveFlow::Flowable

  def display_name
    "#{code} — #{name}"
  end

  flow_field :id, :name, :status   # columnas → aparecen en respuesta + permitted_params
  flow_field :display_name         # método → aparece en respuesta, excluido de permitted_params
end
```

### Controller base

Cada controller generado hereda de la clase configurada en `base_controller` (o la especificada en el bloque `with`) e incluye automáticamente `ActiveFlow::ResourceActions` con todas las acciones CRUD.

Si necesitás sobrescribir una acción o agregar concerns puntuales en un modelo específico, podés reabrir el controller generado:

```ruby
# app/controllers/active_flow/projects_controller.rb
module ActiveFlow
  class ProjectsController < ActiveFlow::ResourceController
    before_action :authenticate_user!

    def index
      # lógica custom
    end
  end
end
```

### Hook `flow_before_action`

Si el modelo define el método de clase `flow_before_action`, el controller lo invoca antes de cada acción. Es útil para autorización, logging u otras validaciones por modelo:

```ruby
class Project < ApplicationRecord
  include ActiveFlow::Flowable

  def self.flow_before_action(action, controller)
    unless controller.current_user&.admin?
      controller.render json: { error: "Forbidden" }, status: :forbidden
    end
  end
end
```

El método recibe el nombre de la acción como Symbol (`:index`, `:show`, etc.) y el controller como segundo argumento, dando acceso a `request`, `params`, `render`, etc. Si el modelo no define el método, se ignora.

---

## Módulo Flowable

`ActiveFlow::Flowable` es un `ActiveSupport::Concern` que expone el DSL. Inclúyelo en el modelo que quieras serializar:

```ruby
class Project < ApplicationRecord
  include ActiveFlow::Flowable

  # ...
end
```

### `flow_field`

Declara uno o más atributos del modelo que serán incluidos en la serialización.

```ruby
flow_field :id, :name, :status
flow_field :priority, type: :integer
flow_field :metadata, type: :json
```

| Argumento | Descripción |
|-----------|-------------|
| `*names`  | Nombres de columnas o métodos del modelo (Symbol o String). |
| `type:`   | Tipo explícito del campo. Si se omite, se infiere desde `columns_hash` de AR (`:unknown` para métodos). |

`flow_field` acepta cualquier método al que el modelo pueda responder — no solo columnas. Los métodos calculados aparecen en la serialización pero quedan automáticamente excluidos de `permitted_params` en el controller.

### `flow_connection`

Declara una relación como **conexión**. A diferencia de `flow_field`, el serializador respeta el DSL del modelo asociado: solo renderiza los `flow_field` declarados en ese modelo, no todos sus atributos.

```ruby
flow_connection :has_many,    :tasks
flow_connection :belongs_to,  :owner
flow_connection :has_one,     :config
```

| Argumento | Descripción |
|-----------|-------------|
| `model_relation_type` | Tipo de asociación AR: `:has_many`, `:belongs_to`, `:has_one`, `:has_and_belongs_to_many`. |
| `*names`  | Nombre de la asociación o cualquier método del modelo que retorne registros. |

**Diferencia clave con `flow_field`:** si declarás una relación con `flow_field :tasks`, el serializador vuelca la colección completa sin filtros. Con `flow_connection :has_many, :tasks`, el serializador mira los `_flow_fields` de `Task` y solo serializa esos campos — respetando el contrato del DSL en cascada:

```ruby
# Task tiene flow_field :id, :title declarados
# Con flow_connection → { id: 1, title: "Setup DB" }
# Con flow_field      → todos los atributos de Task, sin filtro
```

### `flow_all_attributes`

Atajo que registra **todas las columnas** de la tabla como `flow_field`, con posibilidad de excluir algunas.

```ruby
flow_all_attributes                         # todas las columnas
flow_all_attributes except: [:created_at, :updated_at]
```

### `flow_scope`

Define una agrupación nombrada de campos y relaciones ya declarados como `flow_field` y `flow_connection`. Al serializar con ese scope, solo se incluyen los campos y relaciones del grupo.

```ruby
flow_field :id, :name, :status, :priority, :budget, :description
flow_connection :has_many, :tasks
flow_connection :belongs_to, :owner

flow_scope :summary,  fields: [:id, :name, :status]
flow_scope :detailed, fields: [:id, :name, :status, :priority, :budget], connections: [:tasks, :owner]
```

Cada scope puede declarar `fields:` y/o `connections:`. Ambos son opcionales, pero si no se declara `connections:` el scope no serializa ninguna relación — el scope es explícito por diseño.

Los scopes se pasan al serializar:

```ruby
ActiveFlow::Serializer.serialize(project, scope: :summary)
# solo fields: id, name, status — sin edges

ActiveFlow::Serializer.serialize(project, scope: :detailed)
# fields: id, name, status, priority, budget + edges hacia tasks y owner

ActiveFlow::Serializer.to_service_json(project, scope: :summary)
```

Se lanza `ArgumentError` en dos situaciones:

```
# El scope no existe en el modelo
Scope :foo is not defined on Project

# Una connection del scope no está declarada como flow_connection
Connection :comments in scope :detailed is not declared as flow_connection on Project
```

### `flow_all_connections`

Atajo que registra **todas las asociaciones** del modelo como `flow_connection`, con posibilidad de excluir algunas.

```ruby
flow_all_connections                       # todas las asociaciones
flow_all_connections except: [:audits]
```

### Helpers de clase

Estos métodos son generados automáticamente al incluir `Flowable`:

| Método              | Retorna                                                         |
|---------------------|-----------------------------------------------------------------|
| `flow_node_type`    | `String` — nombre singular del modelo (e.g. `"project"`).     |
| `_flow_fields`      | `Array<FieldDefinition>` — campos registrados.                 |
| `_flow_connections` | `Array<ConnectionDefinition>` — conexiones registradas.        |
| `_flow_scopes`      | `Hash<Symbol, ScopeDefinition>` — scopes registrados.          |

---

## Serializador

`ActiveFlow::Serializer` transforma uno o varios registros flowables en distintos formatos JSON. Todos los métodos de clase aceptan tanto un registro individual como una colección (`ActiveRecord::Relation` o `Array`).

### `serialize` — formato React Flow

Genera el formato `{ nodes: [...], edges: [...] }` compatible directamente con React Flow.

```ruby
project = Project.find(1)

ActiveFlow::Serializer.serialize(project)
# =>
# {
#   nodes: [
#     { id: "project-1", type: "project", data: { id: 1, name: "Alpha", status: "active" } },
#     { id: "task-10",   type: "task",    data: { id: 10, title: "Setup DB" } },
#     { id: "task-11",   type: "task",    data: { id: 11, title: "Define API" } }
#   ],
#   edges: [
#     { id: "project-1__task-10", source: "project-1", target: "task-10", label: "has_many" },
#     { id: "project-1__task-11", source: "project-1", target: "task-11", label: "has_many" }
#   ]
# }
```

Cuando se pasa una colección, se devuelven solo nodos (sin edges):

```ruby
ActiveFlow::Serializer.serialize(Project.all)
# => { nodes: [...], edges: [] }
```

**Estructura de un nodo:**

| Campo  | Valor                                              |
|--------|----------------------------------------------------|
| `id`   | `"<node_type>-<record.id>"` (e.g. `"project-1"`) |
| `type` | `flow_node_type` del modelo (e.g. `"project"`)    |
| `data` | Hash con `id` más todos los `flow_field` definidos |

**Estructura de un edge:**

| Campo    | Valor                                          |
|----------|------------------------------------------------|
| `id`     | `"<source_id>__<target_id>"`                  |
| `source` | `id` del nodo origen                           |
| `target` | `id` del nodo destino                          |
| `label`  | Macro de la asociación (`"has_many"`, etc.)    |

---

### `to_service_json` — formato plano para servicios

Genera un hash anidado limpio, ideal para respuestas de API o para pasar a otros servicios.

```ruby
ActiveFlow::Serializer.to_service_json(project)
# =>
# {
#   project: {
#     id: 1,
#     name: "Alpha",
#     status: "active",
#     tasks: [
#       { id: 10, title: "Setup DB" },
#       { id: 11, title: "Define API" }
#     ]
#   }
# }
```

Para colecciones retorna un array de hashes con la misma estructura.

---

### `to_schema` — esquema de tipos

Genera un mapa de tipos de todos los campos y conexiones del modelo. Útil para introspección, documentación automática o configuración dinámica del frontend.

```ruby
ActiveFlow::Serializer.to_schema(Project)
# =>
# {
#   project: {
#     id:     :integer,
#     name:   :string,
#     status: :string,
#     tasks: {
#       relation_type: :has_many,
#       flow_attributes: {
#         id:    :integer,
#         title: :string
#       }
#     }
#   }
# }
```

El tipo de cada campo se resuelve en este orden:
1. El `type:` explícito pasado a `flow_field`.
2. El tipo inferido desde `columns_hash` de ActiveRecord.
3. `:unknown` si no se puede determinar.

---

## Clases internas

Estas clases son value objects usados internamente. No es necesario instanciarlas directamente.

### `FieldDefinition`

Representa un campo registrado con `flow_field`.

| Atributo  | Tipo    | Descripción                              |
|-----------|---------|------------------------------------------|
| `name`    | Symbol  | Nombre del atributo.                     |
| `type`    | Symbol? | Tipo explícito o `nil` si se infiere.   |
| `options` | Hash    | Opciones adicionales (reservado).        |

### `ConnectionDefinition`

Representa una asociación registrada con `flow_connection`.

| Atributo  | Tipo   | Descripción                                                |
|-----------|--------|------------------------------------------------------------|
| `model_relation_type` | Symbol | Tipo de asociación AR: `:has_many`, `:belongs_to`, `:has_one`, etc. |
| `name`    | Symbol | Nombre de la asociación.                                   |
| `options` | Hash   | Opciones adicionales (reservado).                          |

### `Configuration`

Objeto de configuración global accesible vía `ActiveFlow.configuration`.

| Atributo            | Default                   | Descripción |
|---------------------|---------------------------|-------------|
| `auto_include`      | `false`                   | Si es `true`, todos los modelos AR incluyen `Flowable`. |
| `routes_namespace`  | `"flow"`                  | Namespace de rutas para recursos sin `namespace` explícito en `with`. |
| `base_controller`   | `"ActionController::API"` | Controller base para recursos sin `base_controller` explícito en `with`. |

---

## Ejemplo completo

### Modelos

```ruby
# app/models/project.rb
class Project < ApplicationRecord
  include ActiveFlow::Flowable

  has_many :tasks
  has_one  :owner, class_name: "User"

  flow_field :id, :name, :status, :priority
  flow_connection :has_many,   :tasks
  flow_connection :has_one,    :owner
end

# app/models/task.rb
class Task < ApplicationRecord
  include ActiveFlow::Flowable

  belongs_to :project

  flow_field :id, :title, :done
end

# app/models/user.rb
class User < ApplicationRecord
  include ActiveFlow::Flowable

  flow_field :id, :email, :name
end
```

O usando los atajos:

```ruby
class Project < ApplicationRecord
  include ActiveFlow::Flowable

  has_many :tasks
  has_one  :owner, class_name: "User"

  flow_all_attributes except: [:created_at, :updated_at]
  flow_all_connections except: [:audits]
end
```

### Controlador

```ruby
# app/controllers/api/projects_controller.rb
class Api::ProjectsController < ApplicationController
  def show
    project = Project.find(params[:id])
    render json: ActiveFlow::Serializer.serialize(project)
  end

  def index
    render json: ActiveFlow::Serializer.serialize(Project.all)
  end

  def service_data
    project = Project.find(params[:id])
    render json: ActiveFlow::Serializer.to_service_json(project)
  end

  def schema
    render json: ActiveFlow::Serializer.to_schema(Project)
  end
end
```

### Salida de `serialize` para un registro

```json
{
  "nodes": [
    {
      "id": "project-1",
      "type": "project",
      "data": { "id": 1, "name": "Alpha", "status": "active", "priority": 1 }
    },
    {
      "id": "task-10",
      "type": "task",
      "data": { "id": 10, "title": "Setup DB", "done": false }
    },
    {
      "id": "user-3",
      "type": "user",
      "data": { "id": 3, "email": "admin@example.com", "name": "Ana" }
    }
  ],
  "edges": [
    {
      "id": "project-1__task-10",
      "source": "project-1",
      "target": "task-10",
      "label": "has_many"
    },
    {
      "id": "project-1__user-3",
      "source": "project-1",
      "target": "user-3",
      "label": "has_one"
    }
  ]
}
```

Este JSON puede pasarse directamente al prop `initialNodes` / `initialEdges` de un componente React Flow.

---

## Licencia

[MIT](https://opensource.org/licenses/MIT)
