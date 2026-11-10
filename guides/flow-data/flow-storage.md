# Store Flows as JSON

Save a `Jido.Flow` value as a JSON document and load it again with `Jido.Codec`.
You provide a `Jido.Catalog` that maps stable IDs to your modules and atoms. Jido does not write to a database, so you choose where the JSON goes.

## Define the Flow

This Flow reads an order, then charges it. Give each Action an explicit `id:`. Catalog Discovery publishes that ID, and the default is the module name, which changes when you rename the module.

```elixir
defmodule OrderStore.LoadOrder do
  use Jido.Action, id: "orders/load", vsn: 1, name: "load_order"

  @impl true
  def run(%{order_id: order_id}, _context) do
    {:ok, %{order_id: order_id, total_cents: 4_200}}
  end
end

defmodule OrderStore.ChargeOrder do
  use Jido.Action, id: "orders/charge", vsn: 1, name: "charge_order"

  @impl true
  def run(%{total_cents: total_cents}, _context), do: {:ok, %{charged_cents: total_cents}}
end

defmodule OrderStore.Definitions do
  alias Jido.Flow.Ref

  def charge_flow do
    Jido.Flow.new!(%{
      name: "charge_order",
      components: [
        %{
          kind: :step,
          name: "load",
          action: OrderStore.LoadOrder,
          params: %{order_id: Ref.input(:order_id)}
        },
        %{
          kind: :step,
          name: "charge",
          action: OrderStore.ChargeOrder,
          params: %{total_cents: Ref.result("load", :total_cents)}
        }
      ],
      output: Ref.result("charge")
    })
  end
end
```

## Build a Catalog

A document never holds a module name or an atom. It holds Catalog references, so the Catalog must list every target and every atom in the Flow. That includes atom keys in `params` and `meta`, atoms in reference paths, and atom values.

`Jido.Catalog.from_targets!/3` takes a provider module, an OTP application, and a map of `{id, vsn}` keys to registered values.

```elixir
defmodule OrderStore.Catalog do
  def build do
    Jido.Catalog.from_targets!(__MODULE__, :order_store, %{
      {"orders/load", 1} => OrderStore.LoadOrder,
      {"orders/charge", 1} => OrderStore.ChargeOrder,
      {"orders/atoms/order_id", 1} => :order_id,
      {"orders/atoms/total_cents", 1} => :total_cents
    })
  end
end
```

Catalog registers values by ID and version without semantic kinds. The Flow
reader validates target shape and schemas after lookup. Execution validates
callbacks. See [Catalog and Discovery](../data/catalog.md).

## Encode and decode

Pass the Catalog to both functions. Here, `codec: Jido.Flow.Codec` selects the Flow reader directly, so this code does not wait for Catalog Discovery.

```elixir
options = [catalog: OrderStore.Catalog.build(), codec: Jido.Flow.Codec]
flow = OrderStore.Definitions.charge_flow()

{:ok, json} = Jido.Codec.encode_json(flow, options)
{:ok, restored} = Jido.Codec.decode_json(json, options)

^flow = restored
{:ok, %{charged_cents: 4_200}} = Jido.Exec.run(restored, %{order_id: "ord_1001"})
```

Decoding returns the same canonical value that `Jido.Flow.new/1` built, and it does not run an Action. Save `json` in a text or JSON column.

`Jido.Codec.encode/2` and `Jido.Codec.decode/2` do the same work with a map instead of a string. Use them when your database driver handles JSON. For raw text, prefer `Jido.Codec.decode_json/2`, because it also rejects duplicate object keys.

## Handle decode problems

Decoding returns `{:error, issues}`, a list of `Jido.Codec.Issue` structs. Each Issue has a stable `code`, a `path` into the JSON document, a `message`, and `details`. `Jido.Codec.Issue.to_map/1` converts one to JSON-compatible data.

```elixir
options = [catalog: OrderStore.Catalog.build(), codec: Jido.Flow.Codec]
{:ok, json} = Jido.Codec.encode_json(OrderStore.Definitions.charge_flow(), options)
tampered = String.replace(json, "orders/charge", "orders/refund")

{:error, [issue]} = Jido.Codec.decode_json(tampered, options)

:invalid_definition = issue.code
["components", 1, "call", "target", "id"] = issue.path
"unknown flow catalog reference" = issue.message
```

Definition problems are collected, so one document can return several Issues.

| Code | Meaning |
| --- | --- |
| `:invalid_definition` | A Flow field is invalid, or a Catalog reference does not resolve. |
| `:invalid_json` | The text is not valid JSON, or the string is over the byte limit. |
| `:duplicate_key` | A JSON object repeats a key. |
| `:bytes` | A decoded map is over the byte limit in `Jido.Codec.decode/2`. |
| `:depth`, `:collection`, `:nodes` | The document exceeds a resource limit. |
| `:invalid_document` | The document is not a JSON object. |
| `:missing_document_type`, `:invalid_document_type` | The `type` field is missing or is not a string. |
| `:missing_document_vsn`, `:invalid_document_vsn` | The `vsn` field is missing or is not a positive integer. |
| `:unsupported_document` | No codec reads this `type` and `vsn`. `details.supported_vsns` lists what is readable. |

Encoding reports failure differently. It returns `{:error, exception}` with a `Jido.Codec.Error.InvalidError` or `Jido.Codec.Error.InternalError`.

```elixir
partial_catalog =
  Jido.Catalog.from_targets!(OrderStore.Catalog, :order_store, %{
    {"orders/atoms/order_id", 1} => :order_id
  })

{:error, error} =
  Jido.Codec.encode(OrderStore.Definitions.charge_flow(), catalog: partial_catalog)

"flow catalog has no reference for the required target: OrderStore.LoadOrder" =
  Exception.message(error)

[:components, "load", :call] = error.details.path
```

## Use the published Catalog

In an application, Catalog Discovery can build the Catalog for you. It scans application modules and publishes one Catalog and one codec index. Set an allowlist when users can supply stored definitions:

<!-- partial -->
```elixir
config :jido, Jido.Catalog.Discovery,
  applications: [:order_store, :jido],
  modules: [OrderStore.SpecialAction]
```

Action and Flow modules publish themselves. To publish atoms and schemas, define a module with a `__jido_catalog_manifest__/0` function that returns its entries:

<!-- partial -->
```elixir
defmodule OrderStore.CatalogEntries do
  def __jido_catalog_manifest__ do
    [
      %{id: "orders/atoms/order_id", vsn: 1, target: :order_id},
      %{id: "orders/atoms/total_cents", vsn: 1, target: :total_cents}
    ]
  end
end
```

With a published Catalog, you can drop both options:

<!-- partial -->
```elixir
{:ok, json} = Jido.Codec.encode_json(flow)
{:ok, restored} = Jido.Codec.decode_json(json)
```

The first scan runs asynchronously when `:jido` starts. Until it finishes, encoding without `:catalog` raises a `Jido.Codec.Error.InternalError` with the message `Catalog is not ready`. Decoding returns `{:error, [issue]}` with the code `:catalog_not_ready`. Decoding without `:codec` needs the published index even when you pass `:catalog`, so it returns this issue too.

Call `Jido.Catalog.Discovery.ready?/0` to check the scan. Call `Jido.Catalog.Discovery.refresh/1` to rebuild the Catalog after loading more applications.

## Options

`Jido.Codec.encode/2`, `Jido.Codec.encode_json/2`, `Jido.Codec.decode/2`, and `Jido.Codec.decode_json/2` take the same options. An unknown option raises `ArgumentError`.

| Option | Default | Meaning |
| --- | --- | --- |
| `:catalog` | The published Catalog | The `Jido.Catalog` that resolves references. |
| `:codec` | Routed by value or by document `type` and `vsn` | The codec module to use. |
| `:maximum_json_bytes` | 8,388,608 | The largest allowed JSON size in bytes. |

Set an application-wide byte limit with `config :jido, Jido.Codec, maximum_json_bytes: 1_048_576`.

## Limits

| Limit | Value |
| --- | --- |
| JSON size | 8,388,608 bytes by default |
| Nesting depth | 100 levels |
| Items in one list or map | 10,000 |
| Total document nodes | 100,000 |

The value tree limit in a Flow definition is higher, at 256 levels. A value that builds with `Jido.Flow.new/1` can therefore exceed the document nesting limit, and encoding then fails.

## Document format

The current format has `type` `"jido.flow"` and `vsn` `2`. This is the `charge_order` document's first component and output:

```json
{
  "type": "jido.flow",
  "vsn": 2,
  "name": "charge_order",
  "description": null,
  "components": [
    {
      "kind": "call",
      "name": "load",
      "needs": [],
      "meta": {"$type": "map", "entries": []},
      "call": {
        "kind": "action",
        "target": {"id": "orders/load", "vsn": 1},
        "params": {
          "$type": "map",
          "entries": [
            {
              "key": {"$type": "atom", "id": "orders/atoms/order_id", "vsn": 1},
              "value": {
                "$ref": {
                  "source": "input",
                  "component": null,
                  "path": [{"$type": "atom", "id": "orders/atoms/order_id", "vsn": 1}]
                }
              }
            }
          ]
        }
      }
    }
  ],
  "output": {"$ref": {"source": "result", "component": "charge", "path": []}}
}
```

| Form | Holds |
| --- | --- |
| `{"id": ..., "vsn": ...}` | A Catalog reference to a target or schema. |
| `{"$type": "atom", "id": ..., "vsn": ...}` | An atom from the Catalog. |
| `{"$type": "map", "entries": [...]}` | A map. Each entry has a `key` and a `value`. |
| `{"$ref": {...}}` | A `Jido.Flow.Ref`. |
| `{"$expr": {"operator": ..., "operands": [...]}}` | A `Jido.Expr` operation. |

Strings, numbers, Booleans, `null`, and JSON arrays stand for themselves. A plain JSON object is not a valid value, so a hand-written document must use the `$type` map form. `:step` and `:subflow` are stored as `"call"`, and timers, awaits, and selections are stored as `"wait"`. The kinds `step` and `timer` are not accepted in a document.

The `schema` and `output_schema` fields appear only when they differ from `Jido.Joi.map()`.

## Change the stored format

Jido does not upgrade documents automatically. The Flow codec writes and reads `vsn` 2 only. `Jido.Codec.Contract` lets you add a historical reader: a module whose `target/0` returns `nil` and whose `decode/2` reads an older version. To change an Action behind a stored reference, see [Flow Identity](flow-identity-and-versioning.md).

## Related

- [Flow Security](../flow-runtime/flow-security.md) covers untrusted definitions and execution policy.
- [Flow Identity](flow-identity-and-versioning.md) explains how to detect a changed document.
