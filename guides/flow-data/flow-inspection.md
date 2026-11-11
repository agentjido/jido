# Inspect Flows

Read the dependency graph, canonical order, and metadata of a `Jido.Flow` value without running it.
Use these functions in tests, admin tools, and debugging. None of them runs an Action.

This guide uses one Flow:

```elixir
defmodule ShippingInspection.Work do
  use Jido.Action, name: "shipping_work"

  @impl true
  def run(params, _context), do: {:ok, params}
end

defmodule ShippingInspection.Definition do
  alias Jido.Flow.Ref

  def flow do
    Jido.Flow.new!(%{
      name: "ship_order",
      description: "Reserve stock, buy a label, and notify the customer",
      components: [
        %{
          kind: :step,
          name: "notify",
          action: ShippingInspection.Work,
          params: %{tracking: Ref.result("label", :tracking)},
          needs: ["audit"],
          meta: %{team: "fulfillment"}
        },
        %{
          kind: :step,
          name: "label",
          action: ShippingInspection.Work,
          params: %{sku: Ref.result("reserve", :sku)}
        },
        %{
          kind: :step,
          name: "audit",
          action: ShippingInspection.Work,
          params: %{order_id: Ref.input(:order_id)}
        },
        %{
          kind: :step,
          name: "reserve",
          action: ShippingInspection.Work,
          params: %{sku: Ref.input(:sku)}
        }
      ],
      output: Ref.result("notify")
    })
  end
end
```

## Read dependencies

`Jido.Flow.dependencies/1` returns three lists for each component:

- `needs` holds explicit control order.
- `references` holds the components named by result references.
- `effective` holds both, sorted and without duplicates. This set orders the component.

```elixir
flow = ShippingInspection.Definition.flow()

{:ok, dependencies} = Jido.Flow.dependencies(flow)

%{needs: ["audit"], references: ["label"], effective: ["audit", "label"]} =
  dependencies["notify"]

%{needs: [], references: [], effective: []} = dependencies["audit"]
```

You can turn this map into a diagram. This code prints Mermaid edges:

```elixir
{:ok, dependencies} = Jido.Flow.dependencies(ShippingInspection.Definition.flow())

edges =
  for {name, %{effective: effective}} <- Enum.sort(dependencies), source <- effective do
    "#{source} --> #{name}"
  end

["reserve --> label", "audit --> notify", "label --> notify"] = edges
```

See [Flow Dependencies](../flows/flow-dependencies.livemd) for how dependencies affect execution.

## Read the canonical form

`Jido.Flow.to_map/1` returns a plain map of the Flow. Its `components` list is in canonical order: dependency level first, then component name. Source order does not matter.

```elixir
map = Jido.Flow.to_map(ShippingInspection.Definition.flow())

["audit", "reserve", "label", "notify"] = Enum.map(map.components, & &1.name)
%{kind: :call, needs: ["audit"], meta: %{team: "fulfillment"}} = List.last(map.components)
```

The map is for Elixir code. References stay `Jido.Flow.Ref` structs and schemas stay Joi values, so a literal map cannot look like a reference. To get JSON, use [Store Flows as JSON](flow-storage.md).

## Get everything at once

`Jido.Flow.explain/1` combines the canonical form with dependencies and identity. It validates the Flow first, and it returns `{:error, exception}` for an invalid value.

```elixir
{:ok, explanation} = Jido.Flow.explain(ShippingInspection.Definition.flow())

%{
  version: 1,
  kind: :flow,
  name: "ship_order",
  description: "Reserve stock, buy a label, and notify the customer",
  components: [%{name: "audit"} | _],
  dependencies: %{"notify" => %{effective: ["audit", "label"]}},
  output: %Jido.Flow.Ref{source: :result, component: "notify"},
  identity: %{algorithm: :sha256}
} = explanation
```

The `version` key is the version of this inspection format. The `identity` value equals the result of `Jido.Flow.semantic_identity/1`. See [Flow Identity](flow-identity-and-versioning.md).

## Check a value

`Jido.Flow.validate/1` checks the exact canonical structure, including schemas, expressions, references, and cycles. It catches a struct that was edited by hand.

```elixir
flow = ShippingInspection.Definition.flow()
{:ok, ^flow} = Jido.Flow.validate(flow)

edited = put_in(flow.components["audit"].needs, ["notify"])

{:error, error} = Jido.Flow.validate(edited)
"flow dependency graph contains a cycle" = Exception.message(error)
%{components: ["audit", "notify"]} = error.details
```

`Jido.Flow.dependencies/1`, `Jido.Flow.explain/1`, and `Jido.Flow.semantic_identity/1` run the same check.

These checks are inert, so they do not load a target. `Jido.Exec.compile/2` checks that each target is a usable Action or Flow and returns a Runic workflow. It also runs no Action.

```elixir
{:ok, %Runic.Workflow{}} = Jido.Exec.compile(ShippingInspection.Definition.flow(), [])
```

## Inspect a Flow module

A module that uses `Jido.Flow` exposes its definition and metadata. `flow/0` returns the same kind of value as `Jido.Flow.new/1`, so every function above works on it.

```elixir
defmodule ShippingInspection.Label do
  use Jido.Flow,
    id: "shipping/label",
    vsn: 2,
    name: "buy_label",
    description: "Buy a shipping label",
    schema: Jido.Joi.object(%{sku: Jido.Joi.string()})

  flow do
    step "buy", action: ShippingInspection.Work, params: %{sku: input(:sku)}
    output result("buy")
  end
end

"buy_label" = ShippingInspection.Label.name()
{:ok, %{"buy" => %{effective: []}}} = Jido.Flow.dependencies(ShippingInspection.Label.flow())

%{"id" => "shipping/label", "vsn" => 2, "kind" => "flow", "input_schema" => %{}} =
  ShippingInspection.Label.authoring_contract()

{:ok, %{sku: "sku_77"}} = ShippingInspection.Label.validate_params(%{sku: "sku_77"})
{:error, _invalid} = ShippingInspection.Label.validate_params(%{})
```

| Function | Returns |
| --- | --- |
| `flow/0` | The canonical `Jido.Flow` value. |
| `name/0`, `description/0` | The module's metadata. |
| `schema/0`, `output_schema/0` | The input and output Joi schemas. |
| `authoring_contract/0` | A JSON-safe map with `id`, `vsn`, `kind`, `name`, `description`, `input_schema`, and `output_schema`. |
| `validate_params/1`, `validate_output/1` | The validated data or an error, without running Flow work. |
| `step_action/1` | The Action target of one named Step. |

## Related

- [Debug Flows](../flow-runtime/debugging-flows.md) covers what happens during a run.
- [Test Flows](../flow-runtime/testing-flows.livemd) uses these functions in tests.
