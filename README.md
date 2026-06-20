# ActiveFlow

ActiveFlow es una gema Ruby que proporciona un DSL para marcar modelos ActiveRecord como **"flowables"** y serializarlos en formatos JSON compatibles con [React Flow](https://reactflow.dev/), además de un formato plano para servicios/APIs.

## Índice

- [Instalación](#instalación)
- [Configuración](#configuración)
- [Módulo Flowable](#módulo-flowable)
  - [flow_field](#flow_field)
  - [flow_connection](#flow_connection)
  - [flow_model](#flow_model)
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

| Opción         | Tipo    | Default | Descripción |
|----------------|---------|---------|-------------|
| `auto_include` | Boolean | `false` | Incluye `ActiveFlow::Flowable` en **todos** los modelos AR al cargar Rails. |

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
| `*names`  | Uno o más nombres de columnas (Symbol o String). |
| `type:`   | Tipo explícito del campo. Si se omite, se infiere desde `columns_hash` de AR. |

### `flow_connection`

Declara una asociación AR como **conexión** (edge en React Flow).

```ruby
flow_connection :has_many,    :tasks
flow_connection :belongs_to,  :owner
flow_connection :has_one,     :config
```

| Argumento | Descripción |
|-----------|-------------|
| `model_relation_type` | Tipo de asociación AR: `:has_many`, `:belongs_to`, `:has_one`, `:has_and_belongs_to_many`. |
| `*names`  | Nombres de la asociación tal como están definidos en el modelo. |

### `flow_model`

Atajo que registra **todas las columnas** de la tabla como `flow_field`, con posibilidad de excluir algunas.

```ruby
flow_model                         # todas las columnas
flow_model except: [:created_at, :updated_at]
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
| `flow_includes`     | `Array<Symbol>` — nombres de conexiones, útil para `.includes`. |
| `_flow_fields`      | `Array<FieldDefinition>` — campos registrados.                 |
| `_flow_connections` | `Array<ConnectionDefinition>` — conexiones registradas.        |

`flow_includes` es especialmente útil para hacer eager loading antes de serializar:

```ruby
projects = Project.includes(Project.flow_includes).all
ActiveFlow::Serializer.serialize(projects)
```

---

## Serializador

`ActiveFlow::Serializer` transforma uno o varios registros flowables en distintos formatos JSON. Todos los métodos de clase aceptan tanto un registro individual como una colección (`ActiveRecord::Relation` o `Array`).

### `serialize` — formato React Flow

Genera el formato `{ nodes: [...], edges: [...] }` compatible directamente con React Flow.

```ruby
project = Project.includes(Project.flow_includes).find(1)

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

| Atributo       | Default | Descripción                                                   |
|----------------|---------|---------------------------------------------------------------|
| `auto_include` | `false` | Si es `true`, todos los modelos AR incluyen `Flowable`.      |

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

  flow_model except: [:created_at, :updated_at]
  flow_all_connections except: [:audits]
end
```

### Controlador

```ruby
# app/controllers/api/projects_controller.rb
class Api::ProjectsController < ApplicationController
  def show
    project = Project.includes(Project.flow_includes).find(params[:id])
    render json: ActiveFlow::Serializer.serialize(project)
  end

  def index
    projects = Project.includes(Project.flow_includes).all
    render json: ActiveFlow::Serializer.serialize(projects)
  end

  def service_data
    project = Project.includes(Project.flow_includes).find(params[:id])
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
