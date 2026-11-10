# Dynamic Flows

Use `invoke` when runtime data must select an Action or Flow within the current execution. Use `handoff` when the current root Flow must finish and return a successor to run in a new Turn.

## Choose a form

| Need | Use |
| --- | --- |
| Pick among known Actions, with fixed options. | [`choice`](flow-choices.md) |
| Pick the target from runtime data, then keep going in this Flow. | `invoke` |
| End this Flow and give a successor to the host. | `handoff` |

## Define an Invoke

An Invoke calls two Actions. The decision Action receives `params` and returns data. The expander Action receives that data and returns one of these:

- `{:ok, result}` makes `result` the Invoke result.
- `{:continue, input, target}` runs `target` with `input`. Its result becomes the Invoke result.

```elixir
defmodule DynamicFlows.Classify do
  use Jido.Action, name: "dynamic_flows_classify"

  @impl true
  def run(%{cents: cents}, _context) do
    route = if cents >= 10_000, do: :review, else: :automatic
    {:ok, %{route: route, cents: cents}}
  end
end

defmodule DynamicFlows.Expand do
  use Jido.Action, name: "dynamic_flows_expand"

  @impl true
  def run(%{route: :automatic, cents: cents}, _context) do
    {:ok, %{approved_cents: cents}}
  end

  def run(%{route: :review, cents: cents}, _context) do
    {:continue, %{cents: cents}, DynamicFlows.ReviewCharge}
  end
end

defmodule DynamicFlows.ReviewCharge do
  use Jido.Action, name: "dynamic_flows_review_charge"

  @impl true
  def run(%{cents: cents}, _context), do: {:ok, %{approved_cents: cents - 100}}
end

defmodule DynamicFlows.Charge do
  use Jido.Flow, name: "dynamic_flows_charge"

  flow do
    invoke "approve",
      decision: DynamicFlows.Classify,
      expander: DynamicFlows.Expand,
      params: %{cents: input(:cents)}

    step "receipt", approved_cents <- result("approve", :approved_cents) do
      {:ok, %{receipt: "Charged " <> Integer.to_string(approved_cents)}}
    end

    output result("receipt")
  end
end

{:ok, %{receipt: "Charged 500"}} = Jido.Exec.run(DynamicFlows.Charge, %{cents: 500})
{:ok, %{receipt: "Charged 19900"}} = Jido.Exec.run(DynamicFlows.Charge, %{cents: 20_000})
```

An Invoke is a normal component, so other components can read its result, as `"receipt"` does here. A Flow can contain more than one Invoke.

## Select a target

The target can be an Action module, a Flow module, or a `Jido.Flow` value. The selected target runs in the same execution, so a selected Flow can contain nested Invokes.

```elixir
defmodule DynamicFlows.AddFee do
  use Jido.Action, name: "dynamic_flows_add_fee"

  @impl true
  def run(%{cents: cents}, _context), do: {:ok, %{approved_cents: cents + 50}}
end

defmodule DynamicFlows.ExpandToData do
  use Jido.Action, name: "dynamic_flows_expand_to_data"

  @impl true
  def run(%{cents: cents}, _context) do
    target =
      Jido.Flow.new!(%{
        name: "dynamic_flows_generated",
        components: [
          %{
            kind: :step,
            name: "fee",
            action: DynamicFlows.AddFee,
            params: Jido.Flow.Ref.input([])
          }
        ],
        output: Jido.Flow.Ref.result("fee")
      })

    {:continue, %{cents: cents}, target}
  end
end

defmodule DynamicFlows.GeneratedTarget do
  use Jido.Flow, name: "dynamic_flows_generated_target"

  flow do
    invoke "approve",
      decision: DynamicFlows.Classify,
      expander: DynamicFlows.ExpandToData,
      params: %{cents: input(:cents)}

    output result("approve")
  end
end

{:ok, %{approved_cents: 550}} = Jido.Exec.run(DynamicFlows.GeneratedTarget, %{cents: 500})
```

The target validates `input` with its own schema, and it receives the Flow's context. A bad selection fails the Invoke:

- An unknown module fails with "unknown Instruction target".
- A non-map `input` fails with "Invalid params format".
- Input that fails the target's schema returns its validation error.

Use trusted targets. Map external names to modules through an application allow list or a `Jido.Catalog`, and do not create module atoms from runtime input.

Only an expander can return `{:continue, input, target}`. A decision or a Step that returns it fails with "Action continuations are not supported by Runic execution". An expander cannot hand off.

## Hand off to a new Turn

A Handoff selector Action returns `{:handoff, input, target}`. Exec validates the successor and returns it without running it.

```elixir
defmodule DynamicFlows.SelectFulfillment do
  use Jido.Action, name: "dynamic_flows_select_fulfillment"

  @impl true
  def run(%{order_id: order_id}, _context) do
    {:handoff, %{order_id: order_id}, DynamicFlows.Fulfill}
  end
end

defmodule DynamicFlows.Fulfill do
  use Jido.Action, name: "dynamic_flows_fulfill"

  @impl true
  def run(params, _context), do: {:ok, Map.put(params, :fulfilled, true)}
end

defmodule DynamicFlows.PlaceOrder do
  use Jido.Flow, name: "dynamic_flows_place_order"

  flow do
    handoff "next",
      selector: DynamicFlows.SelectFulfillment,
      params: %{order_id: input(:order_id)}

    output result("next")
  end
end

{:handoff, %Jido.Instruction{} = successor, []} =
  Jido.Exec.run(DynamicFlows.PlaceOrder, %{order_id: 7})

%Jido.Instruction{
  target: DynamicFlows.Fulfill,
  kind: :action,
  params: %{order_id: 7},
  context: %{},
  metadata: %{}
} = successor
```

`Jido.Exec.run/4` returns `{:handoff, instruction, effects}`, not `{:ok, ...}`, so match on it. The caller decides what to do with the successor.

```elixir
{:ok, %{order_id: 7, fulfilled: true}} = Jido.Exec.run(successor)
```

### Handoff rules

The compiler rejects these shapes:

- A Flow can contain only one Handoff.
- A Handoff must be the only final component, so nothing can depend on it, and every other component must lead to it.
- The Flow output must be its complete result, `result("next")`, with no path or wrapper.

At runtime:

- Only a `handoff` selector can return `{:handoff, input, target}`. Other Actions fail with "only a Handoff selector can hand off".
- A child Flow cannot hand off for its parent. It fails with "handoff must finish the root Flow".
- The target can be an Action or Flow. Exec validates `input` against its schema before returning.
- The input must be portable data. A process-local value, such as a pid, fails with "durable execution data contains a process-local value".
- The returned Instruction has fresh, empty context and metadata.

Jido does not run the successor for you here. A host can pass the returned Instruction to `Jido.Exec.run/4`, `Jido.Durable`, or an Agent Turn.

## Data form

In a map definition, use `kind: :invoke` with `decision`, `expander`, and `params`, or `kind: :handoff` with `selector` and `params`. See [Flow Data Definitions](../flow-data/flow-data.md).

## Related

- [Nested Flows](nested-flows.livemd) covers a child Flow chosen at compile time.
- [Flow Security](../flow-runtime/flow-security.md) covers trust for runtime targets.
