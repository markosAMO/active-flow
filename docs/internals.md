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

- **`build_edge`** — usa `macro` como `label` del edge React Flow (`"has_many"`)
- **`to_schema`** — usa `macro` como `relation_type` y `name` para reflejar la clase asociada y sus campos

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
