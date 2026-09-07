# Actions, Flows, and Instructions

One Agent route selects an executable from
[Jido Action](https://hexdocs.pm/jido_action/). The target can be an Action
module, a Flow module, or a runtime `Jido.Flow` value.

## Use An Action For One Operation

An Action validates its input and returns one result. In an Agent Turn, the
normal result is the complete next Agent state:

```elixir
defmodule MyApp.CloseOrder do
  use Jido.Action,
    name: "close_order",
    schema: Zoi.object(%{})

  @impl Jido.Action
  def run(_input, %{agent_state: %{status: :open} = state}) do
    {:ok, %{state | status: :closed}}
  end

  def run(_input, _context) do
    {:error, Jido.Error.validation_error("Order must be open")}
  end
end
```

An Action can perform I/O. If later work fails, Jido preserves committed Agent
state but cannot undo I/O that already completed.

## Use A Flow For One Multi-Step Turn

A Flow can run dependent, conditional, parallel, mapped, reduced, iterated, and
nested work. Its final output must be one complete candidate state for the
Agent.

Intermediate Flow results do not become Agent revisions. The complete Flow is
one executable inside one Turn and produces at most one Agent commit.

A sequence of Server calls is different. Each call has its own Turn and commit.
Use separate calls only when every intermediate state is valid and useful.

## Use Instructions At Execution Boundaries

An Instruction stores a target, parameters, context, and metadata. Jido Action
can execute it directly. Agent routes normally provide the target and input
through a Signal, so applications rarely store Instructions in Agent state.

## Return Directives

An Action can return:

```elixir
{:ok, next_state, directives}
```

Jido validates the complete state and Directive list. A direct command returns
the Directives to its caller. A live Agent Server commits state and then
dispatches them.

Action callback extras in a Flow are not collected as Agent Directives. Put
the final Directive list in the terminal Agent result, or use a Plugin that
owns the required effect.

## Test All Three Layers

Test the Action or Flow for its own contract. Test a direct Agent command for
complete state and Plugin rules. Test a live call for persistence, commit, and
post-commit work.

See the [Jido Action guides](https://hexdocs.pm/jido_action/) for complete Flow
authoring and execution details.
