# Flow Waits

This guide shows how to suspend a Flow until an external event or a timer, and how to deliver that event through a durable Agent.

A wait holds no process. The Flow saves its position and releases its Worker, so the wait can last across hibernation and restarts.

## Know where waits can run

A durable Agent Turn or `Jido.Durable` run can host a wait. Both need a persistence adapter.

| Host | Result for a Flow with a wait |
| --- | --- |
| `Jido.AgentServer` with persistence | Runs and suspends |
| `Jido.Durable` with persistence on its Jido instance | Runs and suspends |
| `Jido.AgentServer` without persistence | `{:error, error}` with `details.reason: :unsupported_host` |
| `Jido.Exec.run/4`, direct `Runic.Runner` | No wait host; execution returns an unsupported-host error |

Persistence also requires a stable Jido instance namespace. Configure both
`namespace:` and `persistence:` on the instance before you start an Agent that
can wait. Adding only a persistence adapter fails startup with `persistence
requires a Jido instance with a stable namespace`.

An Action can check for this support with `Jido.Exec.supports?/2`. Callers cannot claim it by passing it in context, because Jido drops the reserved keys.

## Declare a wait

Three components suspend a Flow.

| Component | Waits for | Result |
| --- | --- | --- |
| `await "name", event: "...", match: %{...}` | One matching event | The event payload |
| `timer "name", after_ms: n` | A delay from when the wait opens | `%{fired_at: unix_ms}` |
| `selection "name" do ... end` | The first of several `await` and `timer` options | `%{selected: name, value: value, accepted_at: unix_ms, input_id: id}` |

`match` is a map of payload fields that must be equal. Its values can use Flow references, and they resolve when the wait opens. An empty `match` accepts any payload for that event. Extra payload fields are allowed.

The Flow below waits for a reviewer to approve or reject a refund, and expires after one hour. Later components read the outcome from the result. For a timer option, `value` is `%{fired_at: unix_ms}` and `input_id` is `nil`.

```elixir
defmodule FlowWaitsGuide.ReviewRefund do
  use Jido.Flow,
    name: "flow_waits_guide_review_refund",
    schema: Jido.Joi.object(%{refund_id: Jido.Joi.string()})

  flow do
    selection "review" do
      await "approved", event: "refund.approved", match: %{refund_id: input(:refund_id)}
      await "rejected", event: "refund.rejected", match: %{refund_id: input(:refund_id)}
      timer "expired", after_ms: 3_600_000
    end

    step "record", review <- result("review") do
      {:ok, %{status: review.selected, reviewer: Map.get(review.value, :reviewer, "none")}}
    end

    output result("record")
  end
end

{:error, %{details: %{reason: :unsupported_host, capability: :waits}}} =
  Jido.Exec.run(FlowWaitsGuide.ReviewRefund, %{refund_id: "rf-1"})
```

Use `needs: ["step_name"]` as a field in `selection`, or as an option on `await` and `timer`, to open the wait after earlier work. A wait with a `result` reference in `match` does this for you.

## Host the Flow in an Agent

Route a Signal to the Flow and start the Agent with persistence. This example uses the ETS adapter to save state across Agent stops in the same VM.

The Agent commits nothing while the Flow waits. A Turn's default limit is 60 seconds, so set `turn_timeout: :infinity` when the Flow's own timer owns the deadline.

```elixir
defmodule FlowWaitsGuide.RefundAgent do
  use Jido.Agent, name: "flow_waits_guide_refund_agent"

  state do
    schema Jido.Joi.object(%{
             status: Jido.Joi.string() |> Jido.Joi.default("open"),
             reviewer: Jido.Joi.string() |> Jido.Joi.default("none")
           })
  end

  routes do
    route "refund.review", FlowWaitsGuide.ReviewRefund
  end
end

signal = fn type, data ->
  {:ok, signal} = Jido.Signal.new(type, data, source: "/refunds")
  signal
end

{:ok, _instance} =
  Jido.start_link(name: FlowWaitsGuide.Jido,
    namespace: "flow_waits_guide",
    persistence: {Jido.Persistence.ETS, table: :flow_waits_guide}
  )

{:ok, server} =
  Jido.start_agent(FlowWaitsGuide.Jido, FlowWaitsGuide.RefundAgent,
    id: "refund-agent",
    turn_timeout: :infinity
  )

:ok = Jido.AgentServer.await_ready(server)
{:ok, address} = Jido.agent_address(FlowWaitsGuide.Jido, "refund-agent")

{:ok, %{status: :waiting, turn_id: turn_id, waits: [wait]}} =
  Jido.call(FlowWaitsGuide.Jido, address, signal.("refund.review", %{refund_id: "rf-1"}))
```

`Jido.call/3` returns a waiting result when the Flow suspends. See [Make an Agent Durable](../durability/make-an-agent-durable.livemd) for persistence setup.

## Read open waits

`Jido.status/2` reports the current Turn and its open waits. Each wait is a `Jido.Exec.Wait` struct.

```elixir
%{work_state: :waiting, active_turn_id: ^turn_id, waits: [^wait]} =
  Jido.status(FlowWaitsGuide.Jido, address)

["review"] = wait.path
["approved", "rejected", "expired"] = Enum.map(wait.options, & &1.name)
%{event: "refund.approved", match: %{refund_id: "rf-1"}, deadline: nil} = hd(wait.options)
true = is_integer(Jido.Exec.Wait.next_deadline([wait]))
```

A wait has a stable `id`, the `execution_id` of its Turn, its authored component `path`, resolved `options`, and `opened_at`. Each timer option has an absolute `deadline` in UTC Unix milliseconds. The struct holds portable data only.

Reads stay available while the Flow waits.

## Deliver an event

Send a Signal to the same Agent Address with `Jido.call/3`. Jido matches the Signal type and data against the open waits. Wait until the Flow reports `:waiting` before you send the event.

```elixir
approval = signal.("refund.approved", %{refund_id: "rf-1", reviewer: "ana"})
wrong = put_in(approval.data.refund_id, "rf-2")

{:error, :wait_not_matched} = Jido.call(FlowWaitsGuide.Jido, address, wrong)

%{work_state: :waiting, active_turn_id: ^turn_id, waits: [^wait]} =
  Jido.status(FlowWaitsGuide.Jido, address)

{:ok, %{status: :committed, turn_id: ^turn_id} = completed} =
  Jido.call(FlowWaitsGuide.Jido, address, approval)

{:ok, ^completed} = Jido.call(FlowWaitsGuide.Jido, address, approval)
{:error, :conflicting_input_id} = Jido.call(FlowWaitsGuide.Jido, address, wrong)

%{status: "approved", reviewer: "ana"} = Jido.AgentServer.snapshot(server).agent.state

:ok = Jido.stop(FlowWaitsGuide.Jido)
```

The matching Signal completes the original Turn. While Jido retains that result, the same Signal returns it again. If you reuse that Signal ID with different data, Jido returns `{:error, :conflicting_input_id}`.

## Know how a selection chooses

The earliest time wins. An event's time is the time it was accepted. A timer's time is its deadline. If both land on the same millisecond, the timer wins. Among equal events, the earlier receipt wins, then the earlier option.

A timer resolves with no Signal, so a Flow with only a timer needs nothing delivered.

## Combine waits with other components

- Independent waits can be open at once. Status lists them all. Send a Signal that matches the wait you want to resume.
- Put each wait on the executed root Flow. A nested Flow and a Flow selected by Invoke are atomic authored components and cannot suspend inside that boundary.
- Map and Iterate reject a Flow body that waits. The Flow module fails at compile time with a "wrong target kind" error. Map and Iterate call Action modules only.

## Restart, hibernate, and cancel

A waiting Turn holds no Worker. Hibernation and restore keep the same wait ID and absolute deadline, and completed Actions do not run again. Read status at the stable Agent Address after a restore. Send the matching Signal to that same Address.

`Jido.cancel_turn/3` ends the Turn without committing state. A rejection event is different: it completes the Flow normally and commits whatever the Flow returns.

## Limits

- An AgentServer holds at most 1,024 accepted inputs per execution.
- The Turn timeout stays in force during a wait.
- Your application owns who may deliver a Signal. See [Flow Security](flow-security.md).
- The input limit counts inputs, not bytes. Do not use one Turn for an unbounded stream of events.

## Next steps

- [Durable Turns and Flows](../durability/durable-turns-and-flows.livemd) explains how a Turn recovers.
- [Flow Errors](flow-errors.md) lists what a Turn can return.
