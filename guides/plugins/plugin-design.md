# Plugin Design

A Plugin adds one complete capability to an Agent through optional callbacks in one module. This guide explains what those callbacks can do, when each one runs, and which rules Jido checks when it loads a Plugin.

## When to write a Plugin

Use an Action or a Flow when the work belongs to one route. Use a Plugin when the capability must apply across routes or needs something a route handler cannot own:

- input derived for every Turn
- a private field in Agent state that handlers must not change
- a Directive type that only this capability understands
- a supervised process that lives as long as the Agent
- work that must run after a commit
- a stored form for its state that differs from the live form

## One module, selected callbacks

`use Jido.Plugin` and define only the callbacks you need. Jido selects capabilities from the defined callbacks at compile time. There are no roles and no separate modules to declare.

This Plugin counts completed Turns in a field that it owns:

```elixir
defmodule PluginDesign.TurnCounter do
  use Jido.Plugin

  @impl true
  def state_spec(_opts), do: {:turns, Jido.Joi.integer() |> Jido.Joi.default(0)}

  @impl true
  def reduce(reduction, _opts), do: {:ok, reduction.plugin_state + 1}
end

defmodule PluginDesign.Ticket do
  use Jido.Agent, name: "ticket", plugins: [PluginDesign.TurnCounter]

  state do
    schema Jido.Joi.object(%{open: Jido.Joi.boolean() |> Jido.Joi.default(true)})
  end

  routes do
    signal_source "/support/ticket"

    route "ticket.close", as: :close do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        {:ok, %{context.agent_state | open: false}}
      end
    end
  end
end

ticket = PluginDesign.Ticket.instantiate!(id: "t-1")
%{open: true, turns: 0} = ticket.state

{:ok, closed, []} = PluginDesign.Ticket.cmd(ticket, PluginDesign.Ticket.close_signal!(%{}))
%{open: false, turns: 1} = closed.state
```

The handler returned the complete state without changing `:turns`, and the Plugin updated its own field after the handler succeeded.

## The callbacks

Each callback has one owner. The owner decides where the callback runs and what it can reach.

| Owner | Callback | Purpose | Guide |
|---|---|---|---|
| Agent | `prepare/2` | Derive portable input for this Turn. | Plugin Routing |
| Agent | `select_route/2` | Choose among matching routes. | Plugin Routing |
| Agent | `state_spec/1` | Declare one owned state field and its schema. | Plugin State |
| Agent | `directives/1` | Declare owned Directive types. | Custom Directives |
| Agent | `reduce/2` | Compute the next value of the owned field. | Plugin State |
| AgentServer | `validate_options/1` | Check AgentServer-owned options before startup. | Supervised Resources |
| AgentServer | `admit/3` | Reject a Turn or derive transient input. | Plugin Routing |
| AgentServer | `child_spec/1` | Start one supervised runtime process. | Supervised Resources |
| AgentServer | `await_ready/2` | Report that the runtime can accept work. | Supervised Resources |
| AgentServer | `after_commit/3` | Observe each committed Turn. | Post-Commit Work |
| AgentServer | `dispatch/4` | Run one owned Directive after commit. | Custom Directives |
| AgentServer | `prepare_outbound/4` | Transform or reject an outbound Signal. | Post-Commit Work |
| Persistence | `dump/3`, `load/3` | Convert the owned value for storage. | Plugin Persistence |

Agent callbacks are pure. They run on both the pure path, `Jido.Agent.cmd/3`, and the live path through `Jido.AgentServer`. AgentServer callbacks run only on the live path. On the pure path `context.plugin_inputs[plugin].runtime` is `nil` and no post-commit callback runs. Pure or Live Execution compares the two paths.

## When callbacks run in a Turn

On the live path, one Turn calls Plugin callbacks in this order:

1. `prepare/2` for each Plugin, in declaration order.
2. `admit/3` for each Plugin, in declaration order.
3. `select_route/2` on the one Plugin that defines it, if any.
4. The route handler runs. Jido rejects the result if the handler changed a Plugin-owned field.
5. Jido validates every Directive, and then runs `reduce/2` for each Plugin in declaration order.
6. `dump/3` when the server has persistence configured.
7. Commit. The caller of `Jido.AgentServer.call/3` receives its result.
8. `after_commit/3` for each Plugin, in declaration order.
9. Directives run in batch order. `dispatch/4` handles owned Directives, and `prepare_outbound/4` runs in reverse declaration order for each outbound Signal.

A failure before commit fails the Turn with no state change. A failure after commit does not undo the commit. Post-Commit Work covers that case.

## Declare a Plugin and its options

An Agent lists Plugins as a module or as `{module, map}`. The map needs atom keys and static data. Each module can appear once.

```elixir
defmodule PluginDesign.Labeler do
  use Jido.Plugin, option_keys: [agent: [:label], agent_server: [:strict]]

  alias Jido.Agent.Plugin.Preparation

  @impl true
  def prepare(%Preparation{}, opts), do: {:ok, %{label: opts[:label]}}

  @impl true
  def admit(_runtime, _admission, opts), do: {:ok, %{strict: opts[:strict]}}
end

defmodule PluginDesign.LabeledTicket do
  use Jido.Agent,
    name: "labeled_ticket",
    plugins: [{PluginDesign.Labeler, %{label: "billing", strict: true}}]

  state do
    schema Jido.Joi.object(%{label: Jido.Joi.string() |> Jido.Joi.default("")})
  end

  routes do
    signal_source "/support/labeled"

    route "ticket.label", as: :label do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        prepared = context.plugin_inputs[PluginDesign.Labeler].prepared
        {:ok, %{context.agent_state | label: prepared.label}}
      end
    end
  end
end

labeled = PluginDesign.LabeledTicket.instantiate!(id: "t-2")
{:ok, %{state: %{label: "billing"}}, []} =
  PluginDesign.LabeledTicket.cmd(labeled, PluginDesign.LabeledTicket.label_signal!(%{}))
```

Callbacks receive the options as a keyword list. Without `option_keys`, every callback receives all options. With `option_keys`, each owner receives only its listed keys, so `prepare/2` above sees `:label` and `admit/3` sees `:strict`. Every declared option must then belong to an owner, and each named owner must have at least one callback.

`use Jido.Plugin` accepts these options:

| Option | Default | Meaning |
|---|---|---|
| `:id` | The module name as a string | Stable authoring name for the Plugin. |
| `:vsn` | `1` | Positive integer version. |
| `:option_keys` | `[]` | Maps `:agent`, `:agent_server`, and `:persistence` to their option keys. |
| `:sections` | `[]` | Spark DSL sections that the Plugin adds to the Agent DSL. |
| `:imports` | `[]` | Modules imported into those DSL sections. |

Any other key raises `ArgumentError` at compile time.

## Rules Jido checks

Jido validates a Plugin when it normalizes the declaration, so a bad Plugin fails at definition or at server startup, before a Turn runs.

```elixir
defmodule PluginDesign.ReducerWithoutState do
  use Jido.Plugin

  @impl true
  def reduce(reduction, _opts), do: {:ok, reduction.plugin_state}
end

invalid = PluginDesign.ReducerWithoutState

{:error, %{message: "Agent Plugin reduce/2 requires state_spec/1"}} =
  Jido.Agent.define(%{
    name: "invalid_plugin",
    plugins: [%{id: invalid.id(), provider: invalid, vsn: invalid.vsn(), data: %{}}]
  })
```

The map above is the form a plugin takes in a data-defined Agent. `use Jido.Agent` with the same Plugin raises the same error at compile time.

| Rule | Reason |
|---|---|
| `reduce/2` requires `state_spec/1`. | A reducer needs a field to own. |
| `dump/3` and `load/3` come as a pair and require `state_spec/1`. | Conversion applies only to an owned value. |
| `dispatch/4` requires `directives/1` with at least one type. | Dispatch handles only owned types. |
| An owned Directive needs `reduce/2` or `dispatch/4`. | Something must consume it. |
| Each owned Directive module defines a struct and `validate/1`. | Jido validates every Directive before commit. |
| A Directive type has one owner and cannot be a built-in type. | Dispatch must be unambiguous. |
| A state key is unique across Plugins and absent from the domain schema. | One field has one owner. |
| Only one Plugin can define `select_route/2`. | Route choice must have one authority. |

## Add Agent syntax

A Plugin can extend the Agent DSL with Spark sections. Three more callbacks turn that syntax into validated data: `lower/2` reads the DSL, `normalize/1` validates the result from any authoring path, and `verify/2` checks it against the complete Agent definition. The normalized data arrives in other callbacks as options.

```elixir
defmodule PluginDesign.Escalation do
  defstruct [:name, :after_turns, :__spark_metadata__]
end

defmodule PluginDesign.EscalationPolicy do
  @escalation %Spark.Dsl.Entity{
    name: :escalation,
    target: PluginDesign.Escalation,
    args: [:name],
    schema: [name: [type: :atom, required: true], after_turns: [type: :pos_integer, required: true]]
  }
  @section %Spark.Dsl.Section{
    name: :escalations,
    schema: [on: [type: :string, required: true]],
    entities: [@escalation]
  }

  use Jido.Plugin, id: "support.escalation_policy", sections: [@section]

  alias Spark.Dsl.Extension

  @impl true
  def lower(dsl, _config) do
    {:ok,
     %{
       on: Extension.get_opt(dsl, [:escalations], :on),
       levels: dsl |> Extension.get_entities([:escalations]) |> Enum.map(&Map.take(&1, [:name, :after_turns]))
     }}
  end

  @impl true
  def verify(data, definition) do
    if Enum.any?(definition.routes, &(&1.path == data.on)),
      do: :ok,
      else: {:error, :escalation_signal_needs_a_route}
  end

  @impl Jido.Plugin
  def state_spec(_opts), do: {:escalated, Jido.Joi.list(Jido.Joi.atom()) |> Jido.Joi.default([])}

  @impl Jido.Plugin
  def reduce(reduction, opts) do
    reached =
      for %{name: name, after_turns: after_turns} <- opts[:levels],
          reduction.candidate_state.replies >= after_turns,
          name not in reduction.plugin_state,
          do: name

    {:ok, reduction.plugin_state ++ reached}
  end
end

defmodule PluginDesign.EscalatingTicket do
  use Jido.Agent, name: "escalating_ticket", plugins: [PluginDesign.EscalationPolicy]

  state do
    schema Jido.Joi.object(%{replies: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  escalations do
    on "ticket.reply"
    escalation :supervisor, after_turns: 1
    escalation :manager, after_turns: 2
  end

  routes do
    signal_source "/support/escalating"

    route "ticket.reply", as: :reply do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        {:ok, %{context.agent_state | replies: context.agent_state.replies + 1}}
      end
    end
  end
end

escalating = PluginDesign.EscalatingTicket.instantiate!(id: "t-3")
reply = PluginDesign.EscalatingTicket.reply_signal!(%{})
{:ok, once, []} = PluginDesign.EscalatingTicket.cmd(escalating, reply)
[:supervisor] = once.state.escalated
{:ok, twice, []} = PluginDesign.EscalatingTicket.cmd(once, reply)
[:supervisor, :manager] = twice.state.escalated
```

A Plugin can also add routes through `derive_routes/1`. See Plugin Routing.

## Next steps

- Write a Stateful Plugin builds a Plugin step by step.
- Plugin Routing covers Turn input and route selection.
- Audit Records shows a bundled Plugin that uses these contracts.
