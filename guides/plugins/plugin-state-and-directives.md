# Plugin State

A Plugin can own one field in the complete Agent state. This guide gives the rules for declaring that field, reducing it, and reading it.

## Declare the field

`state_spec/1` receives the Agent-owned options and returns one of:

- `{key, schema}` to own the field `key`, validated by a `Jido.Joi` schema.
- `:none` to own nothing.
- `{:error, reason}` to reject the declaration.

Jido merges the field into the Agent's schema, so domain fields and Plugin fields share one Map and one validation pass. Give the schema a default so that the Agent can instantiate without a value.

```elixir
defmodule PluginStateGuide.ReplyLog do
  use Jido.Plugin, option_keys: [agent: [:limit]]

  alias Jido.Agent.Plugin.Reduction

  @impl true
  def state_spec(_opts) do
    {:reply_log,
     Jido.Joi.object(%{
       count: Jido.Joi.integer() |> Jido.Joi.min(0),
       recent: Jido.Joi.list(Jido.Joi.string())
     })
     |> Jido.Joi.default(%{count: 0, recent: []})}
  end

  @impl true
  def reduce(%Reduction{} = reduction, opts) do
    before = reduction.state_before.last_reply
    current = reduction.candidate_state.last_reply

    if current == before do
      {:ok, reduction.plugin_state}
    else
      {:ok,
       %{
         count: reduction.plugin_state.count + 1,
         recent: Enum.take([current | reduction.plugin_state.recent], opts[:limit])
       }}
    end
  end
end

defmodule PluginStateGuide.Ticket do
  use Jido.Agent,
    name: "ticket",
    plugins: [{PluginStateGuide.ReplyLog, %{limit: 2}}]

  state do
    schema Jido.Joi.object(%{last_reply: Jido.Joi.string() |> Jido.Joi.default("")})
  end

  routes do
    signal_source "/support/ticket"

    route "ticket.reply", as: :reply do
      action %{text: text},
        schema: Jido.Joi.object(%{text: Jido.Joi.string()}),
        context: context do
        {:ok, %{context.agent_state | last_reply: text}}
      end
    end

    route "ticket.touch", as: :touch do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        {:ok, context.agent_state}
      end
    end
  end
end

ticket = PluginStateGuide.Ticket.instantiate!(id: "t-1")
%{last_reply: "", reply_log: %{count: 0, recent: []}} = ticket.state

reply = fn agent, text ->
  {:ok, next, []} = PluginStateGuide.Ticket.cmd(agent, PluginStateGuide.Ticket.reply_signal!(%{text: text}))
  next
end

after_replies = ticket |> reply.("first") |> reply.("second") |> reply.("third")
%{count: 3, recent: ["third", "second"]} = after_replies.state.reply_log
```

These state keys fail when Jido loads the Plugin:

- `nil` and `:__struct__`, which are reserved.
- A key that another Plugin on the Agent owns.
- A key that appears in the Agent's domain schema.

The schema must be a `Jido.Joi` schema that contains only static data.

## Write the reducer

`reduce/2` runs once per successful Turn, for each Plugin that defines it, in declaration order. It runs on Turns that change nothing and on Turns with no Directives, so return `reduction.plugin_state` when the Turn does not concern the Plugin.

It receives a `Jido.Agent.Plugin.Reduction`:

| Field | Value |
|---|---|
| `:plugin` | The Plugin module. |
| `:agent_id`, `:agent_module` | The Agent's identity. |
| `:signal` | The Signal of this Turn. |
| `:state_before` | Complete Agent state when the Turn started. |
| `:candidate_state` | Complete state after the handler and earlier reducers. |
| `:plugin_state` | Current value of this Plugin's field. |
| `:prepared_input` | The value that this Plugin's `prepare/2` returned, or `nil`. |
| `:directives` | All validated Directives in the batch, including those of other Plugins. |

A reducer returns `{:ok, value}` for its own field or `{:error, reason}` to fail the Turn. It cannot write another field. Later Plugins see the new value in `:candidate_state`, so Plugin order matters when one reducer reads another Plugin's field.

Jido validates the returned value against the Plugin's schema. An invalid value, an invalid return shape, or a raised exception fails the Turn, and nothing commits.

```elixir
defmodule PluginStateGuide.BadCounter do
  use Jido.Plugin

  @impl true
  def state_spec(_opts), do: {:counter, Jido.Joi.integer() |> Jido.Joi.default(0)}

  @impl true
  def reduce(_reduction, _opts), do: {:ok, "not an integer"}
end

defmodule PluginStateGuide.BadTicket do
  use Jido.Agent, name: "bad_ticket", plugins: [PluginStateGuide.BadCounter]

  routes do
    signal_source "/support/bad"

    route "ticket.touch", as: :touch do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        {:ok, context.agent_state}
      end
    end
  end
end

bad = PluginStateGuide.BadTicket.instantiate!(id: "t-2")

{:error, %{message: "Plugin-owned Agent state field is invalid"}} =
  PluginStateGuide.BadTicket.cmd(bad, PluginStateGuide.BadTicket.touch_signal!(%{}))
```

## Reduce from Directives

A handler that needs to change a Plugin's field returns a Directive that the Plugin owns, and the reducer applies it. This keeps one writer for the field and lets the handler state its intent as data. [Custom Directives](plugin-custom-directives.livemd) shows this pattern.

## Owner protection

Handlers can read Plugin-owned fields in `context.agent_state`, but must return them unchanged. A changed field fails the Turn with `details.code` set to `:plugin_state_owner_violation`, before any reducer runs. `Jido.Agent.set/2` rejects these fields as well. `instantiate/1` can set them, which suits tests and restored data.

```elixir
tampering = PluginStateGuide.Ticket.instantiate!(id: "t-3", state: %{reply_log: %{count: 9, recent: []}})
%{count: 9} = tampering.state.reply_log
```

## Read the field from outside

| Reader | Call |
|---|---|
| A process outside the Agent | `Jido.AgentServer.plugin_state/3` with the server and the Plugin module |
| A process that a Plugin runtime owns | `Jido.AgentServer.Plugin.state/2` with its `Jido.Plugin.Init` value |
| A pure test | `agent.state[key]` |

Both server calls return `{:ok, value}` with the committed value, or `{:error, :plugin_not_found}` for a Plugin that the Agent does not declare. A declared Plugin with no state returns `{:ok, nil}`.

```elixir
{:ok, _instance} = Jido.start(name: PluginStateGuide.Jido)
{:ok, server} = Jido.start_agent(PluginStateGuide.Jido, PluginStateGuide.Ticket, id: "t-live")
:ok = Jido.AgentServer.await_ready(server)

{:ok, _agent, []} = Jido.AgentServer.call(server, PluginStateGuide.Ticket.reply_signal!(%{text: "hello"}))

{:ok, %{count: 1, recent: ["hello"]}} = Jido.AgentServer.plugin_state(server, PluginStateGuide.ReplyLog)
{:error, :plugin_not_found} = Jido.AgentServer.plugin_state(server, PluginStateGuide.BadCounter)
```

## Next steps

- [Custom Directives](plugin-custom-directives.livemd) adds owned Directive types.
- [Plugin Persistence](plugin-persistence.md) converts the field for storage.
- [Agent State and Schemas](../agents/agent-state-and-schemas.md) covers the complete state Map.
