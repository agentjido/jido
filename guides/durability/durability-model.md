# Durability Model

This guide explains what Jido saves for an Agent, when each write happens, and what recovery reads back. Read it before you choose a storage adapter or decide which Turns must survive a crash.

## What persistence adds

An Agent is durable when its AgentServer runs with a `persistence:` adapter. The server then keeps one record for each Agent and reads that record whenever an activation starts.

The record key is the exact `{namespace, partition, id}` tuple of a `Jido.Agent.Ref`. The Agent module is checked against the record, but it is not part of the key. A durable Agent therefore needs an instance with a stable `:namespace`.

Jido saves four kinds of data:

| Data | Where it lives | What it holds |
| --- | --- | --- |
| Agent checkpoint | Agent record | Complete definition, committed state, and fingerprints of the code it references |
| Revision | Agent record | The number that orders writes to this record |
| Turn receipt | Agent record, optional | The accepted Signals, portable context, Flow fingerprint, deadline, and status of the latest durable Turn |
| Flow graph | Separate execution keys in the same store | Flow progress between steps, removed after the Turn ends |

Jido does not save caller handles, queued Signals, process state, timers, or the progress of post-commit effects. A complete list by failure type is in [Recovery Limits](recovery-and-effect-limits.md).

## What each Turn writes

Each successful commit writes one new revision before the server publishes the new state. A route to an authored Flow also saves the accepted work first. A route to an Action is an ordinary Turn, so it has no acceptance write and no recovery point.

| Turn | Writes | Revision change | After a crash before commit |
| --- | --- | --- | --- |
| Action route succeeds | Agent with new state | +1 | The Turn is gone |
| Action route fails | None | 0 | The Turn is gone |
| Flow route succeeds | Acceptance, then Agent with `:completed` receipt | +2 | The same Turn resumes |
| Flow route fails or is cancelled | Acceptance, then unchanged Agent with terminal receipt | +2 | The same Turn resumes |

Completion saves the candidate Agent and the terminal receipt in one write. Step checkpoints go to the execution keys and do not change the revision.

The next example runs all four rows against an in-memory adapter.

```elixir
defmodule DurabilityModelGuide.Charge do
  use Jido.Action,
    name: "durability_model_charge",
    schema: Jido.Joi.object(%{cents: Jido.Joi.integer()})

  @impl Jido.Action
  def run(%{cents: cents}, %{agent_state: state}) do
    if cents > 0,
      do: {:ok, %{state | balance_cents: state.balance_cents + cents}},
      else: {:error, Jido.Error.validation_error("charge must be positive")}
  end
end

defmodule DurabilityModelGuide.ChargeFlow do
  use Jido.Flow,
    name: "durability_model_charge_flow",
    schema: Jido.Joi.object(%{cents: Jido.Joi.integer()})

  flow do
    step "charge", action: DurabilityModelGuide.Charge, params: %{cents: input(:cents)}
    output result("charge")
  end
end

defmodule DurabilityModelGuide.Invoice do
  use Jido.Agent, name: "durability_model_invoice"

  state do
    schema Jido.Joi.object(%{balance_cents: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/guides/durability_model"
    route "invoice.charge", DurabilityModelGuide.Charge, as: :charge
    route "invoice.charge_flow", DurabilityModelGuide.ChargeFlow, as: :charge_flow
  end
end

alias DurabilityModelGuide.Invoice
alias Jido.AgentServer, as: Server

{:ok, _} =
  Jido.start_link(
    name: DurabilityModelGuide.Jido,
    namespace: "guides/durability-model",
    persistence: {Jido.Persistence.ETS, table: :durability_model_guide}
  )

{:ok, server} =
  Jido.start_agent(DurabilityModelGuide.Jido, Invoice, id: "invoice-1", persistence: :inherit)

:ok = Server.await_ready(server)

revision = fn -> Server.snapshot(server).state_version end

0 = revision.()

{:ok, signal} = Invoice.charge_signal(%{cents: 500})
{:ok, _agent, []} = Server.call(server, signal)
1 = revision.()

{:ok, signal} = Invoice.charge_signal(%{cents: -1})
{:error, _reason} = Server.call(server, signal)
1 = revision.()

{:ok, signal} = Invoice.charge_flow_signal(%{cents: 250})
{:ok, _agent, []} = Server.call(server, signal)
3 = revision.()
%{status: :completed} = Server.status(server).durable_turn

{:ok, signal} = Invoice.charge_flow_signal(%{cents: -1})
{:error, _reason} = Server.call(server, signal)
5 = revision.()
%{status: :failed} = Server.status(server).durable_turn

%{balance_cents: 750} = Server.agent(server).state
```

A revision counts writes to the record. It does not count successful Turns, and an unchanged state can still produce a new revision. [Revisions and Conflicts](durable-revisions-and-conflicts.md) has the exact rules.

## What recovery does

Every activation start follows the same path:

1. The activation supervisor starts the AgentServer, which registers as `:starting`.
2. The server reads the record and validates its format, identity, revision, and code references.
3. The server restores the Agent and the latest Turn receipt, and starts Plugins.
4. The server reports ready.
5. A receipt with status `:running` resumes that Flow at the last confirmed step. A terminal receipt does nothing.

Two different things can start this path:

- **OTP restarts within a live BEAM.** The activation supervisor restarts a killed AgentServer. The supervisor allows three restarts in five seconds and then stops the activation. The record stays intact.
- **The application activates after BEAM loss.** Jido has no recovery scanner. Your application must know which Agents to activate, and it must call `Jido.activate_agent/4` or `Jido.thaw/4` for each one.

Recovery never falls back to fresh state. A missing, deleted, or invalid record, or changed code, stops the activation with a reason. Only `Jido.activate_agent/4` and `persistence_mode: :restore_or_create` create a record, and only after a read returns `:not_found`.

## Who owns each responsibility

| Owner | Responsibility |
| --- | --- |
| OTP supervisors | Restart processes inside a live BEAM |
| AgentServer | Accept, checkpoint, restore, cancel, and commit the current Turn |
| Agent | Hold committed domain state |
| Flow runtime | Hold the graph and run the next runnable step |
| Application | Own storage, keep compatible code deployed, and activate known Agents after BEAM loss |

## Without persistence

With no adapter, an activation keeps a local checkpoint in memory. A killed AgentServer restarts with the last committed Agent and revision, but an interrupted Flow does not resume. The checkpoint ends with the activation.

## What durability does not give you

- **Exactly-once work.** An Action interrupted by a crash runs again. See [Recovery Limits](recovery-and-effect-limits.md).
- **Writer ownership across nodes.** Compare-and-swap rejects a stale write, but it is not a lease. See [Revisions and Conflicts](durable-revisions-and-conflicts.md).
- **Family snapshots.** Each topology member saves its own record. See [Durable Topology](durable-topology.md).
- **Durability beyond your store.** The ETS adapter loses all data when the BEAM stops. See [Local Stores](../storage/local-persistence-adapters.md) and the [Persistence Matrix](../reference/persistence-adapter-matrix.md).

## Next steps

- [Make an Agent Durable](make-an-agent-durable.livemd)
- [Durable Agent Activation](durable-agent-activation.livemd)
- [Durable Turns and Flows](durable-turns-and-flows.livemd)
