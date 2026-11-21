# Authoring Runtime Data

Build a Flow while your application runs, from an admin form, a database row, or a generated plan.
This guide shows how to turn that data into a validated `Jido.Flow` value without letting the data add code.

## Choose an authoring form

Jido has three ways to author a Flow. Each one produces the same canonical `Jido.Flow` struct, so everything after authoring works the same way.

| Form | Use it when | Entry point |
| --- | --- | --- |
| Flow module DSL | You know the definition at compile time. | `use Jido.Flow` |
| Data definition | Your code assembles the definition at run time. | `Jido.Flow.new/1` |
| Stored document | You load a saved definition. | `Jido.Codec.decode_json/2` |

Start with the DSL when you can. It supports inline Step bodies and compile-time extensions, which the other two forms do not. See [Flows](../flows/flows.md).

## Build a Flow from a request

This example builds an invoice pipeline from a list of step names. The list could come from an admin form or a settings table. The data selects steps from a fixed map, and an unknown name stops the build.

```elixir
defmodule InvoicePipeline.ApplyDiscount do
  use Jido.Action, name: "apply_discount"

  @impl true
  def run(%{total_cents: total, percent: percent}, _context) do
    {:ok, %{total_cents: total - div(total * percent, 100)}}
  end
end

defmodule InvoicePipeline.AddTax do
  use Jido.Action, name: "add_tax"

  @impl true
  def run(%{total_cents: total, percent: percent}, _context) do
    {:ok, %{total_cents: total + div(total * percent, 100)}}
  end
end

defmodule InvoicePipeline.Builder do
  alias Jido.Flow.Ref

  @steps %{
    "apply_discount" => InvoicePipeline.ApplyDiscount,
    "add_tax" => InvoicePipeline.AddTax
  }

  def build(name, requested_steps) do
    with {:ok, components} <- components(requested_steps) do
      Jido.Flow.new(%{
        name: name,
        components: components,
        output: Ref.result(List.last(requested_steps)["name"])
      })
    end
  end

  defp components(requested_steps) do
    requested_steps
    |> Enum.reduce_while({:ok, [], Ref.input(:total_cents)}, fn step, {:ok, built, total} ->
      case Map.fetch(@steps, step["name"]) do
        {:ok, action} ->
          component = %{
            kind: :step,
            name: step["name"],
            action: action,
            params: %{total_cents: total, percent: step["percent"]}
          }

          {:cont, {:ok, [component | built], Ref.result(step["name"], :total_cents)}}

        :error ->
          {:halt, {:error, {:unknown_step, step["name"]}}}
      end
    end)
    |> case do
      {:ok, built, _total} -> {:ok, Enum.reverse(built)}
      {:error, reason} -> {:error, reason}
    end
  end
end

{:ok, flow} =
  InvoicePipeline.Builder.build("invoice_pricing", [
    %{"name" => "apply_discount", "percent" => 10},
    %{"name" => "add_tax", "percent" => 20}
  ])

{:ok, %{total_cents: 10_800}} = Jido.Exec.run(flow, %{total_cents: 10_000})

{:error, {:unknown_step, "delete_invoice"}} =
  InvoicePipeline.Builder.build("invoice_pricing", [%{"name" => "delete_invoice"}])
```

Each Step reads the previous Step through a result reference. The reference creates the dependency, so the order of the `components` list does not matter. See [Flow Data Definitions](flow-data.md) for every component kind.

## Keep run data out of the definition

A Flow definition describes work. It does not hold the values for one run. Pass those values as input or context, and read them with `Jido.Flow.Ref.input/1` and `Jido.Flow.Ref.context/1`.

```elixir
alias Jido.Flow.Ref

tenant_flow =
  Jido.Flow.new!(%{
    name: "invoice_tax_for_tenant",
    components: [
      %{
        kind: :step,
        name: "add_tax",
        action: InvoicePipeline.AddTax,
        params: %{total_cents: Ref.input(:total_cents), percent: Ref.context(:tax_percent)}
      }
    ],
    output: Ref.result("add_tax")
  })

{:ok, %{total_cents: 1_100}} =
  Jido.Exec.run(tenant_flow, %{total_cents: 1_000}, %{tax_percent: 10})
```

A literal in `params` is part of the definition, and changing it changes the [Flow identity](flow-identity-and-versioning.md). A value read from input or context does not.

## Know what a definition can contain

A definition holds portable data. These values are accepted in `params`, `meta`, and `output`:

- `nil`, Booleans, numbers, UTF-8 strings, and atoms;
- proper lists of accepted values;
- plain maps with string, atom, or non-negative integer keys;
- `Jido.Flow.Ref` references and `Jido.Expr` operations, except in `meta`.

Functions, tuples, PIDs, and other structs are rejected. The error names the path to the bad value.

```elixir
{:error, error} =
  Jido.Flow.new(%{
    name: "invoice_callback",
    components: [
      %{
        kind: :step,
        name: "add_tax",
        action: InvoicePipeline.AddTax,
        params: %{on_done: fn -> :ok end}
      }
    ],
    output: Jido.Flow.Ref.result("add_tax")
  })

"invalid Flow expression" = Exception.message(error)
[:components, 0, :call, :params, :on_done] = error.details.path
```

## Check targets before you trust them

Data can select existing code. It cannot add code. A data definition accepts only module atoms as targets, so it rejects anonymous functions, MFA tuples, and inline bodies.

`Jido.Flow.new/1` is inert. It checks structure, references, and dependency cycles, but it does not load or check the target module. Call `Jido.Exec.compile/2` to check targets before you save or run a Flow.

```elixir
unchecked =
  Jido.Flow.new!(%{
    name: "invoice_wrong_target",
    components: [%{kind: :step, name: "format", action: String}],
    output: Jido.Flow.Ref.result("format")
  })

{:ok, ^unchecked} = Jido.Flow.validate(unchecked)

{:error, compile_error} = Jido.Exec.compile(unchecked, [])
:missing_behaviour = compile_error.details.reason
```

Map untrusted names to modules through your own allowlist, as the builder above does, or through a `Jido.Catalog`. A Catalog is an inventory, and finding an Entry does not authorize its target. Apply your application's policy before execution.

## Reuse targets that modules own

You do not need to write every target by hand. These functions return values that a data definition can use:

- `Jido.Flow.from_action/1` wraps an Action module in a one-step Flow.
- A generated Flow module's `step_action/1` returns the Action target of a named Step, including an inline Step. It does not copy that Step's parameters, dependencies, or metadata.
- A Flow module can be the target of a `:subflow` component.

```elixir
defmodule InvoicePipeline.Rounding do
  use Jido.Flow, name: "invoice_rounding"

  flow do
    step "round", total_cents <- input(:total_cents) do
      {:ok, %{total_cents: div(total_cents + 50, 100) * 100}}
    end

    output result("round")
  end
end

rounded =
  Jido.Flow.new!(%{
    name: "invoice_rounded",
    components: [
      %{
        kind: :step,
        name: "round",
        action: InvoicePipeline.Rounding.step_action("round"),
        params: %{total_cents: Jido.Flow.Ref.input(:total_cents)}
      }
    ],
    output: Jido.Flow.Ref.result("round")
  })

{:ok, %{total_cents: 1_300}} = Jido.Exec.run(rounded, %{total_cents: 1_260})

{:ok, one_step} = Jido.Flow.from_action(InvoicePipeline.AddTax)

{:ok, %{total_cents: 110}} =
  Jido.Exec.run(one_step, %{total_cents: 100, percent: 10})
```

Data definitions and stored documents do not load [Flow extensions](../flows/flow-modules.md). Extensions change module DSL source only.

## Related

- [Store Flows as JSON](flow-storage.md) saves a Flow value and loads it again.
- [Inspect Flows](flow-inspection.md) reads the dependency graph of a value you built.
- [Documents and Views](../agents/agent-documents-and-views.md) covers Agent documents. `Jido.Agent.define!/1` builds an Agent definition from a map.
