# Map and Reduce

Use `map` to run one Action for each list item and `reduce` to fold a list through an Action. This guide also covers `parallel`, which runs different Actions at the same point in a Flow.

## Map then Reduce

```elixir
defmodule FlowCollections.PriceLine do
  use Jido.Action, name: "flow_collections_price_line"

  @impl true
  def run(%{sku: sku, quantity: quantity, position: position}, _context) do
    {:ok, %{sku: sku, cents: quantity * 500, position: position}}
  end
end

defmodule FlowCollections.AddCents do
  use Jido.Action, name: "flow_collections_add_cents"

  @impl true
  def run(%{total: total, cents: cents}, _context), do: {:ok, %{total: total + cents}}
end

defmodule FlowCollections.Invoice do
  use Jido.Flow, name: "flow_collections_invoice"

  flow do
    map "lines",
      collection: input(:lines),
      action: FlowCollections.PriceLine,
      params: %{sku: item(:sku), quantity: item(:quantity), position: item_index()}

    reduce "total" do
      collection result("lines")
      initial %{total: 0}
      action FlowCollections.AddCents
      params %{total: accumulator(:total), cents: item(:cents)}
    end

    output %{lines: result("lines"), total: result("total", :total)}
  end
end

{:ok,
 %{
   lines: [
     %{sku: "A-1", cents: 1000, position: 0},
     %{sku: "B-2", cents: 500, position: 1}
   ],
   total: 1500
 }} =
  Jido.Exec.run(FlowCollections.Invoice, %{
    lines: [%{sku: "A-1", quantity: 2}, %{sku: "B-2", quantity: 1}]
  })
```

`result("lines")` reads the complete Map result without consuming it, so the output can return both the list and the total. The Map Action runs once per item, however many components read the result.

Both components accept keyword and field-block forms.

## Fields

| Field | Component | Required | Meaning |
| --- | --- | --- | --- |
| name (first argument) | both | yes | The unique component name. |
| `collection` | both | yes | A value that resolves to the items. |
| `action` | both | yes | The Action module to call for each item. |
| `params` | both | yes | The parameters for each call. |
| `initial` | `reduce` | yes | The first accumulator. |
| `on_error` | `map` | no | `:fail_fast` by default, or `:collect_errors`. |
| `needs`, `meta` | both | no | As in [Steps and Output](flow-steps.md). |

`collection` and `initial` can read `input`, `context`, and `result`. Only `params` can use the local references:

| Reference | Map | Reduce | Value |
| --- | --- | --- | --- |
| `item(path)` | yes | yes | The current item. |
| `item_index()` | yes | yes | The zero-based position. |
| `item_id()` | yes | yes | A runtime identifier for this item. |
| `accumulator(path)` | no | yes | The current accumulator. |

Use `item_index()` for position. Do not use `item_id()` as an execution or business identifier.

## Map rules

- An empty collection returns `[]` and calls no Action.
- Results keep input order, even when calls finish out of order.
- The target must be an Action module. A Flow module raises `CompileError`, and inline bodies are not supported.
- An item whose Action returns effects adds them to the Flow's effects in item order.

## Reduce rules

- Each call's result becomes the next accumulator, and the result of the component is the last accumulator.
- An empty collection returns `initial` and calls no Action.
- `initial` must be a map or a `Jido.Action.Output` value. A list or scalar compiles, then fails at runtime, even for an empty collection.
- Calls run one item at a time, in list order. A failure stops the fold before the next item.

```elixir
{:ok, %{lines: [], total: 0}} = Jido.Exec.run(FlowCollections.Invoice, %{lines: []})
```

## Map error modes

With the default `on_error: :fail_fast`, the first item failure fails the Map. `error.details` holds `item_index` and `node_path`. With `max_concurrency: 1`, later items do not start. At higher settings, do not assume which items ran.

With `on_error: :collect_errors`, an item failure becomes a record, and the Map succeeds. The result has one record for each item, in input order.

```elixir
defmodule FlowCollections.CheckAmount do
  use Jido.Action, name: "flow_collections_check_amount"

  @impl true
  def run(%{amount: amount}, _context) when amount < 0 do
    {:error, Jido.Error.execution_error("negative amount")}
  end

  def run(%{amount: amount}, _context), do: {:ok, %{amount: amount}}
end

defmodule FlowCollections.CheckAll do
  use Jido.Flow, name: "flow_collections_check_all"

  flow do
    map "checked",
      collection: input(:amounts),
      action: FlowCollections.CheckAmount,
      params: %{amount: item()},
      on_error: :collect_errors

    output %{checked: result("checked")}
  end
end

{:ok, %{checked: [first, second, third]}} =
  Jido.Exec.run(FlowCollections.CheckAll, %{amounts: [1, -2, 3]})

%{status: :ok, value: %{amount: 1}} = first
%{status: :ok, value: %{amount: 3}} = third

%{
  status: :error,
  error: %{
    type: :execution_error,
    message: "negative amount",
    details: %{item_index: 1},
    retryable?: true
  }
} = second
```

The `error` record is plain data from `Jido.Error.to_map/1`. A reference failure in `params`, such as a missing item key, also becomes a record in this mode. Choose the mode on purpose. Jido adds no retry or fallback. To retry a call, see [Execution Policy](../actions/action-execution-policy.md).

## Concurrency

Map items can run concurrently when `max_concurrency` is greater than `1`. Pass it to `Jido.Exec.run/4`:

```elixir
{:ok, %{total: 1500}} =
  Jido.Exec.run(
    FlowCollections.Invoice,
    %{lines: [%{sku: "A-1", quantity: 2}, %{sku: "B-2", quantity: 1}]},
    %{},
    max_concurrency: 2
  )
```

See [Execution](../flow-runtime/execution.md) for runtime options.

## Run different Actions with Parallel

Use `parallel` when different Actions, not one Action over many items, belong at the same point. It needs at least one `action`, and the names must be unique within the component. Fields go in a block, including `on_error`, and each `action` takes a module or an inline body.

```elixir
defmodule FlowCollections.Lookups do
  use Jido.Flow, name: "flow_collections_lookups"

  flow do
    parallel "lookups" do
      action "amount", FlowCollections.CheckAmount, params: %{amount: input(:amount)}

      action "customer", customer_id <- input(:customer_id) do
        {:ok, %{customer_id: customer_id, active: true}}
      end
    end

    output %{lookups: result("lookups")}
  end
end

{:ok,
 %{
   lookups: [
     %{name: "amount", value: %{amount: 5}},
     %{name: "customer", value: %{customer_id: 9, active: true}}
   ]
 }} = Jido.Exec.run(FlowCollections.Lookups, %{amount: 5, customer_id: 9})
```

The result is a list in declaration order, not a map. Read an entry by position, such as `result("lookups", [0, :value])`.

The default `on_error: :fail_fast` fails the component on an Action failure. With `on_error :collect_errors`, each entry has `status`, and failed entries have `error` in place of `value`:

```elixir
defmodule FlowCollections.TolerantLookups do
  use Jido.Flow, name: "flow_collections_tolerant_lookups"

  flow do
    parallel "lookups" do
      on_error :collect_errors
      action "first", FlowCollections.CheckAmount, params: %{amount: input(:first)}
      action "second", FlowCollections.CheckAmount, params: %{amount: input(:second)}
    end

    output %{lookups: result("lookups")}
  end
end

{:ok,
 %{
   lookups: [
     %{name: "first", status: :ok, value: %{amount: 1}},
     %{name: "second", status: :error, error: %{message: "negative amount"}}
   ]
 }} = Jido.Exec.run(FlowCollections.TolerantLookups, %{first: 1, second: -1})
```

A `parallel` target must be an Action. Flow modules are rejected at compile time. The DSL field reference in `Jido.Flow` lists each field.

## Data form

In a map definition, use `kind: :map`, `kind: :reduce`, or `kind: :parallel`. See [Flow Data Definitions](../flow-data/flow-data.md).
