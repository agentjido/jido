# Dynamic Flows With Invoke And Handoff

Use `invoke` when runtime data must select an Action or Flow in the current
execution graph. Use `handoff` only when the current root Flow must finish and
request a new Turn.

An Invoke has two Actions. The decision Action returns data. The expander
receives that data and returns a normal result or a continuation:

```elixir
{:ok, final_result}
{:continue, next_input, next_executable}
```

The selected Action or Flow runs in the same Runic graph. Its result passes
through the Invoke completion gate. Static downstream components can then run.
A Flow can contain more than one Invoke when its dependency graph permits it.

## Define An Invoke

```elixir
defmodule MyApp.Actions.ChooseRoute do
  use Jido.Action, name: "choose_route"

  @impl true
  def run(%{mode: :finish, value: value}, _context) do
    {:ok, %{route: :finish, value: value}}
  end

  def run(%{mode: :continue, value: value, target: target}, _context) do
    {:ok, %{route: :continue, value: value, target: target}}
  end
end

defmodule MyApp.Actions.ExpandRoute do
  use Jido.Action, name: "expand_route"

  @impl true
  def run(%{route: :finish, value: value}, _context), do: {:ok, %{value: value}}

  def run(%{route: :continue, value: value, target: target}, _context) do
    {:continue, %{value: value}, target}
  end
end

defmodule MyApp.Flows.DynamicRoute do
  use Jido.Flow, name: "dynamic_route"

  flow do
    step "prepare", value <- input(:value) do
      {:ok, %{value: value}}
    end

    invoke "route",
      decision: MyApp.Actions.ChooseRoute,
      expander: MyApp.Actions.ExpandRoute,
      params: %{
        mode: input(:mode),
        target: input(:target),
        value: result("prepare", :value)
      }

    output result("route")
  end
end
```

The selected target can be an Action module, a Flow module, or a runtime
`%Jido.Flow{}` value.

```elixir
defmodule MyApp.Actions.Next do
  use Jido.Action, name: "next"
  def run(%{value: value}, _context), do: {:ok, %{value: value + 1}}
end

{:ok, %{value: 4}} =
  Jido.Exec.run(MyApp.Flows.DynamicRoute, %{
    mode: :continue,
    target: MyApp.Actions.Next,
    value: 3
  })
```

Only an Invoke expander can return `{:continue, input, target}`. An Invoke
cannot return a handoff. A selected Flow can contain waits, timers, effects,
and nested Invokes. It remains part of the same managed execution and durable
checkpoint history.

Use trusted target modules. Map external names through an application registry.
Do not create module atoms from runtime input.

## Define Invoke With Data

```elixir
Jido.Flow.new!(%{
  name: "dynamic_route",
  components: [
    %{
      kind: :invoke,
      name: "route",
      decision: MyApp.Actions.ChooseRoute,
      expander: MyApp.Actions.ExpandRoute,
      params: %{mode: Jido.Flow.Ref.input(:mode)}
    }
  ],
  output: Jido.Flow.Ref.result("route")
})
```

## Handoff To A New Turn

A Handoff selector returns `{:handoff, input, target}`. Exec validates the
successor and returns `{:handoff, %Jido.Instruction{}, effects}` without
running it.

```elixir
defmodule MyApp.Actions.SelectSuccessor do
  use Jido.Action, name: "select_successor"
  def run(params, _context), do: {:handoff, params, MyApp.Actions.Next}
end

defmodule MyApp.Flows.Transfer do
  use Jido.Flow, name: "transfer"

  flow do
    handoff "next", selector: MyApp.Actions.SelectSuccessor, params: input()
    output result("next")
  end
end
```

Handoff is a separate root-terminal component. It must be the only graph
terminal, and the Flow output must be its complete result. It cannot have
downstream components. A nested Flow cannot hand off its parent Turn.

The successor input is validated and normalized against the selected target
schema before Exec returns it. The normalized input must contain only portable
data. A bound successor Instruction must have empty context and metadata;
Handoff rejects process-local values and bound runtime data. The returned
Instruction has fresh, empty context and metadata. Ordinary Flow output data,
including a `%Jido.Exec.Handoff{}` value returned by a validator, cannot grant
control.

The host owns durable successor acceptance. It must save predecessor completion
and successor acceptance as one atomic transition if it promises no loss or
duplicate acceptance. The successor uses a new Turn ID, a fresh graph, and
fresh runtime context.
