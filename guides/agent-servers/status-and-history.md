# Status and Turn History

`Jido.AgentServer.status/2` returns a bounded view of a running Agent, and `Jido.AgentServer.history/1` returns summaries of finished Turns. This guide lists each field and how to read it.

Both are safe to call while a Turn runs. Neither reads Agent state or Signal data, so they suit logs and dashboards.

```elixir
defmodule StatusGuide.Invoices do
  use Jido.Agent, name: "invoices"

  state do
    schema Jido.Joi.object(%{paid: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/billing"

    route "invoice.pay", as: :pay do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        {:ok, %{context.agent_state | paid: context.agent_state.paid + 1}}
      end
    end
  end
end

{:ok, _instance} = Jido.start(name: StatusGuide.Jido)
{:ok, invoices} = Jido.start_agent(StatusGuide.Jido, StatusGuide.Invoices, id: "acct-1", debug: true)
:ok = Jido.AgentServer.await_ready(invoices)

%Jido.AgentServer.Status{phase: :idle, ready?: true, agent_id: "acct-1", state_version: 0, active: nil} =
  Jido.AgentServer.status(invoices)
```

## Status fields

`Jido.AgentServer.Status` holds no PIDs, references, or functions.

| Field | Meaning |
| --- | --- |
| `phase` | The public phase. See below. |
| `ready?` | `true` after startup, and `false` while a composition change is settling. |
| `plugin_count` | The number of Plugins in the current definition. |
| `activation` | `:supervised`, or `:bare` for a worker with no activation. |
| `parent` | The parent relationship without its live handle, or `nil`. See [Child Agent Adoption](child-agents-and-adoption.md). |
| `agent_id`, `jido`, `partition` | The Agent's identity in its instance. |
| `state_version` | The revision of the committed Agent. Each commit adds one. |
| `active` | The running Turn, or `nil`. |
| `effects` | Progress through post-commit effects, as `%{total: n, completed: n}`, or `nil`. |
| `waits` | Open durable Flow waits. See [Flow Waits](../flow-runtime/flow-waits.md). |
| `durable_turn` | The saved Turn's `:id`, `:status`, `:chain_id`, and `:chain_order`, or `nil`. |
| `last_outcome` | The summary of the last finished Turn, or `nil`. |
| `last_effect_outcome` | The summary of the last effect batch, or `nil`. |
| `error_count` | Failed Turns and reported effect errors since the last commit. See [Agent Lifecycle](agent-activation-control.md#handle-failed-turns). |
| `owner_count` | Attached owner processes. See [Control Activations](inspect-and-control-activations.livemd). |
| `idle_timeout`, `idle_policy` | The configured idle behavior. |
| `admission` | `%{mode: mode, postponed: count, limit: limit, message_queue_len: count}`. |

### Phases

`phase` has five values:

| Phase | Meaning |
| --- | --- |
| `:initializing` | The server is restoring saved state or starting Plugins. |
| `:idle` | No Turn is active. |
| `:running` | A Turn is active. Read `active.stage` for the detail. |
| `:waiting` | A durable Flow is suspended on a wait. |
| `:handoff_pending` | A durable Handoff is about to start its next Turn. |

### The active Turn

`active` holds the Turn's `:turn_id`, `:signal_id`, `:start_version`, `:committed_version`, and `:stage`. `:committed_version` is `nil` until the Turn commits. `:stage` is the internal phase, which can be `:preparing`, `:starting`, `:running`, `:settling`, `:cleaning`, `:reconfiguring`, `:saving`, `:policy`, `:effects`, `:waiting`, or `:hibernating`. Use it for display, and match on `phase` in code.

Pass `active.turn_id` to `Jido.AgentServer.cancel_turn/3` to cancel that exact Turn.

### Admission modes

| Mode | Meaning |
| --- | --- |
| `:open` | New Turns are accepted. |
| `:quiescing` | Admission is closed, and the server is draining work. |
| `:quiesced` | Admission is closed, and the server has settled. |
| `:blocked` | An uncertain hibernation save closed admission. `Jido.AgentServer.resume/2` returns `{:error, :unsafe_resume}`. |

## Outcome summaries

`last_outcome` and each history entry are the same map. A successful Turn looks like this:

```elixir
{:ok, _agent, []} = Jido.AgentServer.call(invoices, StatusGuide.Invoices.pay_signal!(%{}))

%{
  status: :succeeded,
  stage: :commit,
  committed?: true,
  state_version_before: 0,
  state_version_after: 1,
  directive_count: 0,
  turn_id: turn_id,
  signal_id: signal_id,
  duration_ms: duration_ms
} = Jido.AgentServer.status(invoices).last_outcome

{is_binary(turn_id), is_binary(signal_id), is_integer(duration_ms)}
```

| `status` | Meaning | `committed?` |
| --- | --- | --- |
| `:succeeded` | The Turn committed. Effects can still fail after this. | `true` |
| `:failed` | The Turn returned an error. | `false` |
| `:cancelled` | A cancel request stopped the Turn. | `false` |
| `:timed_out` | The `:turn_timeout` expired. | `false` |
| `:indeterminate` | The server stopped before the Turn reached a result. | `false` |

For a Turn that does not commit, `stage` names the phase where the Turn stopped, and both version fields hold the unchanged revision. A Turn in a durable Handoff chain also has `:chain_id` and `:chain_order`.

```elixir
unknown = Jido.Signal.new!("invoice.refund", %{}, source: "/billing")
{:error, %Jido.Error.ValidationError{}} = Jido.AgentServer.call(invoices, unknown)

%{status: :failed, committed?: false, state_version_after: 1} =
  Jido.AgentServer.status(invoices).last_outcome

Jido.AgentServer.status(invoices).error_count
```

## Effect summaries

The Turn outcome reports the commit. `last_effect_outcome` reports the work after it, so read both. It has `:turn_id`, `:status`, `:completed`, `:total`, `:committed_version`, and `:stage`. `:stage` is `:directive`, or `:after_commit` when a Plugin hook failed. `:status` is `:succeeded`, `:failed`, `:timed_out`, or `:indeterminate`. `call/3` returns at commit, before effects run, so this field can lag behind the return value. See [Runtime Effects](runtime-directives-and-effects.md).

## Keep Turn history

`Jido.AgentServer.history/1` returns outcome summaries in chronological order. It is opt-in. Start the Agent with `debug: true`, or the list stays empty. `:debug_max_events` sets how many to keep, from 1 to 10,000, with a default of 100. The oldest entries go first.

```elixir
[%{status: :succeeded}, %{status: :failed}] = Jido.AgentServer.history(invoices)

{:ok, plain} = Jido.start_agent(StatusGuide.Jido, StatusGuide.Invoices, id: "acct-2")
{:ok, _agent, []} = Jido.AgentServer.call(plain, StatusGuide.Invoices.pay_signal!(%{}))
[] = Jido.AgentServer.history(plain)
%{status: :succeeded} = Jido.AgentServer.status(plain).last_outcome
```

History and `last_outcome` live in the worker process. A worker restart clears them, and the instance does not save them. Use telemetry for a lasting record.

The `:debug` option controls history only. `set_debug/2` on `Jido.Telemetry` changes log detail for an instance, and today it affects only persistence events.

## Read committed data

| Function | Use it for |
| --- | --- |
| `Jido.AgentServer.agent/2` | The committed Agent. |
| `Jido.AgentServer.snapshot/2` | The committed Agent and revision, read together. It returns `{:error, :not_ready}` during startup. |
| `Jido.AgentServer.plugin_state/3` | One Plugin's committed field. It returns `{:error, :plugin_not_found}` for an unknown Plugin. |
| `Jido.AgentServer.children/2` | Live tagged children. |
| `Jido.AgentServer.members/3` | Live topology members in slot order. |

`Jido.status/3`, `Jido.agent/3`, `Jido.plugin_state/4`, and `Jido.children/3` do the same through a `Jido.Agent.Ref`.

## Related

- [Runtime Debugging](../operations/runtime-state-and-debugging.md) uses these views to diagnose a live system.
- [Telemetry and Tracing](../operations/telemetry-tracing-and-logs.md) lists the runtime events.
