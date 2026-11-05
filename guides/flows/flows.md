# Flows

A Flow is a named graph of Action calls that you declare as data and run through `Jido.Exec`. This guide explains what a Flow contains, what Jido checks for you, and when to reach for one instead of a plain Action.

## A complete Flow

```elixir
defmodule Orders.LoadOrder do
  use Jido.Action,
    name: "load_order",
    schema: Jido.Joi.object(%{id: Jido.Joi.integer()})

  @impl true
  def run(%{id: id}, _context), do: {:ok, %{id: id, subtotal: 120}}
end

defmodule Orders.PriceOrder do
  use Jido.Flow,
    name: "price_order",
    description: "Loads an order and adds tax.",
    schema: Jido.Joi.object(%{id: Jido.Joi.integer()}),
    output_schema: Jido.Joi.object(%{id: Jido.Joi.integer(), total: Jido.Joi.number()})

  flow do
    step "load",
      action: Orders.LoadOrder,
      params: %{id: input(:id)}

    step "tax", subtotal <- result("load", :subtotal), inline: [context: ctx] do
      {:ok, %{amount: subtotal * ctx.tax_rate}}
    end

    output %{
      id: result("load", :id),
      total: result("load", :subtotal) + result("tax", :amount)
    }
  end
end

{:ok, %{id: 7, total: 132.0}} =
  Jido.Exec.run(Orders.PriceOrder, %{id: 7}, %{tax_rate: 0.1})
```

The parts of this module map to the parts of every Flow:

- `use Jido.Flow` sets the name, description, and input and output schemas. Only `name:` is required.
- `flow do` declares named components. `"load"` calls an Action module. `"tax"` declares its Action inline.
- `result("load", :subtotal)` reads data from another component and makes `"tax"` depend on `"load"`.
- `output` builds the Flow result. Every Flow requires a non-nil output, and it must be the last declaration.

## What a Flow is

A Flow describes control and data movement. It holds no executable code of its own. Actions hold the behavior, and the Flow holds small records that name each Action and describe its parameters. `Orders.PriceOrder.flow/0` returns a `Jido.Flow` struct with the canonical graph:

```elixir
%Jido.Flow{name: "price_order", components: components} = Orders.PriceOrder.flow()

["load", "tax"] = components |> Map.keys() |> Enum.sort()
```

Because that value is data, Jido can validate it, compare it, derive a stable identity for it, and store it as JSON when every target has a trusted identifier. See [Flow Data Definitions](../flow-data/flow-data.md) and [Store Flows as JSON](../flow-data/flow-storage.md).

Parameter fields use a small language: references such as `input/1` and `result/2`, literal data, and the operators in [Expressions](flow-expressions.md). They cannot call application functions. Put that work in an Action or an inline body.

## Choose a Flow or an Action

Write an Action when one function does the work. Write a Flow when you need any of these:

- several Actions connected by data, with the order derived from that data;
- routing on data, fan-out over a list, or a bounded loop;
- a definition you can inspect, test as a graph, or store; or
- a graph you run as one unit from an Agent route or another Flow.

A Flow module also satisfies the Action module contract for metadata, schemas, and validation, so it provides `name/0`, `schema/0`, `validate_params/1`, and `validate_output/1`. `Orders.PriceOrder.run/2` is a convenience call to `Jido.Exec.run/3`.

```elixir
"price_order" = Orders.PriceOrder.name()
{:ok, %{id: 7}} = Orders.PriceOrder.validate_params(%{id: 7})
{:ok, %{total: 132.0}} = Orders.PriceOrder.run(%{id: 7}, %{tax_rate: 0.1})
```

To wrap one existing Action as a Flow, use `Jido.Flow.from_action/1`. It passes the complete input to the Action and returns the Action's result.

## Components

A `flow` block declares one or more components. At least one is required.

| Declaration | Purpose | Guide |
| --- | --- | --- |
| `step` | Calls one Action, or a child Flow when the target is a Flow module. | [Steps and Output](flow-steps.md), [Nested Flows](nested-flows.livemd) |
| `choice` | Runs the first option whose condition is true, or a required fallback. | [Choices and Conditions](flow-choices.md) |
| `map` | Runs one Action for each list item. | [Map and Reduce](flow-collections.md) |
| `reduce` | Folds a list through one Action, one item at a time. | [Map and Reduce](flow-collections.md) |
| `parallel` | Runs different named Actions and joins their results. | [Map and Reduce](flow-collections.md) |
| `iterate` | Runs one Action as a bounded loop over local state. | [Iterate and State](flow-iterate-state.md) |
| `invoke` | Selects an Action or Flow at runtime and continues in this graph. | [Dynamic Flows](dynamic-flows.md) |
| `handoff` | Ends the root Flow and returns a successor to run in a new Turn. | [Dynamic Flows](dynamic-flows.md) |
| `timer`, `await`, `selection` | Wait for a deadline or a host input under a host that supports waits. | [Flow Waits](../flow-runtime/flow-waits.md) |

`Jido.Exec.run/4` does not support waits. A Flow with a `timer`, `await`, or `selection` returns `{:error, %Jido.Error.ValidationError{}}` from that function with the message "execution host does not support waits".

## What Jido checks at compile time

The Flow compiler rejects a module with a `CompileError` at the declaration line for these problems:

- a missing or nil `output`, or an `output` that is not the last declaration;
- a duplicate component name;
- a `result` reference or `needs` entry that names an unknown component;
- a dependency cycle, including a component that reads its own result;
- a reference used outside its scope, such as `item()` in a Step;
- an unsupported parameter expression, such as a function call or a tuple; and
- a target of the wrong kind, such as a Flow module as a Map target.

Data-dependent problems appear at runtime as structured errors. Examples are a missing input key or a non-Boolean condition. See [Flow Errors](../flow-runtime/flow-errors.md).

## How a Flow runs

`Jido.Exec.run/4` validates the input against `schema`, compiles the Flow to a Runic workflow, runs components as their dependencies complete, and validates the result against `output_schema`.

- Source order creates no dependency. See [Flow Dependencies](flow-dependencies.livemd).
- Every component runs, including one whose result the output does not read.
- An Action can return effect requests in a third tuple element. Exec collects them from each successful component and returns `{:ok, output, effects}`.
- A failed component fails the Flow unless it uses `on_error: :collect_errors`. A failed Flow returns no effects.

## Next steps

- [Flow DSL Tour](flow-language.livemd) runs every common declaration in one Livebook.
- [Build Your First Flow](../start-here/build-your-first-flow.livemd) is the step-by-step introduction.
- [Execution](../flow-runtime/execution.md) covers run options, timeouts, and concurrency.
