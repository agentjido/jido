# Flow Waits

This guide shows how to suspend a Flow until an external event or a timer, and how to deliver that event through a durable Agent.

A wait holds no process. The Flow saves its position and releases its Worker, so the wait can last across hibernation and restarts.

## Know where waits can run

Only a durable Agent Turn can host a wait. It needs a Flow route and a persistence setting on the Agent or its Jido instance.

| Host | Result for a Flow with a wait |
| --- | --- |
| `Jido.AgentServer` with persistence | Runs and suspends |
| `Jido.AgentServer` without persistence | `{:error, error}` with `details.reason: :unsupported_host` |
| `Jido.Exec.run/4`, `Jido.Exec.start/6` | `{:error, error}` with `details.reason: :unsupported_host` |

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

Route a Signal to the Flow and start the Agent with persistence. This example stores files in a temporary directory.

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

storage = Path.join(System.tmp_dir!(), "flow-waits-guide-#{System.unique_integer([:positive])}")
{:ok, _instance} = Jido.start_link(name: FlowWaitsGuide.Jido, namespace: "flow_waits_guide")

{:ok, server} =
  Jido.start_agent(FlowWaitsGuide.Jido, FlowWaitsGuide.RefundAgent,
    id: "refund-agent",
    persistence: {Jido.Persistence.File, path: storage},
    turn_timeout: :infinity
  )

:ok = Jido.AgentServer.await_ready(server)
pending = Jido.AgentServer.submit(server, signal.("refund.review", %{refund_id: "rf-1"}))
```

`Jido.AgentServer.submit/3` returns a handle at once. See [Make an Agent Durable](../durability/make-an-agent-durable.livemd) for persistence setup.

## Read open waits

`Jido.AgentServer.status/2` reports `phase: :waiting` and the open waits as `Jido.Exec.Wait` structs. Poll or react to your own trigger, because the wait opens after the Turn has started.

```elixir
wait_for_open = fn wait_for_open, attempts_left ->
  case Jido.AgentServer.status(server) do
    %{phase: :waiting, waits: [wait]} -> wait
    _not_yet when attempts_left > 0 -> Process.sleep(10) && wait_for_open.(wait_for_open, attempts_left - 1)
  end
end

wait = wait_for_open.(wait_for_open, 200)

["review"] = wait.path
["approved", "rejected", "expired"] = Enum.map(wait.options, & &1.name)
%{event: "refund.approved", match: %{refund_id: "rf-1"}, deadline: nil} = hd(wait.options)
true = is_integer(Jido.Exec.Wait.next_deadline([wait]))
```

A wait has a stable `id`, the `execution_id` of its Turn, a `path` through nested Flows, resolved `options`, and `opened_at`. Each timer option has an absolute `deadline` in UTC Unix milliseconds. Save the `id` wherever your callback needs it. The struct holds portable data only.

Reads stay available while the Flow waits. Other state-changing Turns stay queued until this Turn finishes.

## Deliver an event

Build a Signal and call `Jido.AgentServer.deliver_wait/4` with the wait ID. The Signal `type` selects the event, its `data` is the payload, and its `id` identifies a retry.

`:ok` means the input was saved. It does not mean the Flow finished. Wait for the handle from `Jido.AgentServer.submit/3`, or read status later.

```elixir
{:error, %{details: %{reason: :unmatched_input}}} =
  Jido.AgentServer.deliver_wait(server, wait.id, signal.("refund.approved", %{refund_id: "rf-2"}))

{:error, %{details: %{reason: :stale_target}}} =
  Jido.AgentServer.deliver_wait(server, "not-a-wait", signal.("refund.approved", %{refund_id: "rf-1"}))

approval = signal.("refund.approved", %{refund_id: "rf-1", reviewer: "ana"})
:ok = Jido.AgentServer.deliver_wait(server, wait.id, approval)

{:ok, %{state: %{status: "approved", reviewer: "ana"}}, []} = Jido.AgentServer.await(pending)
```

`Jido.AgentServer.deliver_wait/4` can return:

| Result | Meaning | What to do |
| --- | --- | --- |
| `:ok` | Saved. A retry with the same Signal is harmless | Wait for the Turn |
| `details.reason: :unmatched_input` | The event or payload does not match | Fix the Signal |
| `details.reason: :stale_target` | No open wait has this ID | Read status again |
| `details.reason: :input_limit` | The execution holds 1,024 accepted inputs | Stop sending inputs |
| `{:error, :not_waiting}` | The wait has not opened, the Worker is running, or the Turn finished | Read status, then retry or stop |

A caller timeout does not cancel delivery. Retry with the same Signal and wait ID. Jido has no mailbox for early input, so deliver only after `status` shows the wait.

```elixir
{:error, :not_waiting} = Jido.AgentServer.deliver_wait(server, wait.id, approval)

:ok = Jido.stop(FlowWaitsGuide.Jido)
File.rm_rf!(storage)
```

## Know how a selection chooses

The earliest time wins. An event's time is the time it was accepted. A timer's time is its deadline. If both land on the same millisecond, the timer wins. Among equal events, the earlier receipt wins, then the earlier option.

A timer resolves with no Signal, so a Flow with only a timer needs nothing delivered.

## Combine waits with other components

- Independent waits can be open at once. `status` lists them all, and you deliver to each by ID. They can resolve in any order.
- A nested Flow can wait. The wait `path` includes the parent, and effects from earlier children are kept.
- An Invoke can select a target Flow that waits.
- Map and Iterate reject a Flow body that waits. The Flow module fails at compile time with a "wrong target kind" error. Map and Iterate call Action modules only.

## Restart, hibernate, and cancel

A waiting Turn holds no Worker. Hibernation and restore keep the same wait ID and absolute deadline, and completed Actions do not run again. The process that called `Jido.AgentServer.submit/3` loses its handle, so read `status` and the Agent after a restore.

`Jido.AgentServer.cancel/2` ends the Turn without committing state. Late input then returns `{:error, :not_waiting}`. A rejection event is different: it completes the Flow normally and commits whatever the Flow returns.

## Limits

- An AgentServer holds at most 1,024 accepted inputs per execution.
- The Turn timeout stays in force during a wait.
- Your application owns who may deliver a Signal. See [Flow Security](flow-security.md).
- The input limit counts inputs, not bytes. Do not use one Turn for an unbounded stream of events.

## Next steps

- [Durable Turns and Flows](../durability/durable-turns-and-flows.livemd) explains how a Turn recovers.
- [Flow Errors](flow-errors.md) lists what a Turn can return.
