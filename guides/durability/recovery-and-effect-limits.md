# Recovery Limits

This reference lists what survives each failure, which work can repeat, and what Jido leaves to your application. Check it when you design a Flow that calls an external system or plan for node loss.

## What survives each failure

The table assumes persistence is on. BEAM loss also assumes an adapter that keeps data outside the BEAM.

| Failure | Who restarts it | Committed Agent | Pending Flow Turn | Action route Turn in progress | Queued Signals | Caller handles |
| --- | --- | --- | --- | --- | --- | --- |
| AgentServer killed | Activation supervisor | Restored | Resumes | Lost | Lost | Return an error |
| Flow worker killed | Activation supervisor, after the server stops | Restored | Resumes | Not applicable | Lost | Return an error |
| Activation killed | Instance supervisor, or the root for a member | Restored | Resumes | Lost | Lost | Return an error |
| `Jido.AgentServer.stop/3` or `Jido.stop/1` | Your application | Saved | Resumes after activation | Lost | Lost | Return an error |
| `Jido.AgentServer.hibernate/2` | Your application | Saved | Finished or cancelled first, unless waiting | Finished or cancelled first | Rejected | Return an error for a Turn saved while waiting |
| BEAM loss | Your application | Restored after activation | Resumes after activation | Lost | Lost | Gone |
| Required write fails | Your application | The last stored revision | Resumes after activation, if its receipt is `:running` | Lost | Lost | Return an error |

The ETS adapter loses every record when the BEAM stops. Node, disk, and power loss depend on your store. [Persistence Matrix](../reference/persistence-adapter-matrix.md) compares adapters.

## Limits on automatic restart

- An activation allows three restarts in five seconds. After that it stops and stays stopped. The record is intact, so activate the Agent again.
- Recovery after a failed required write, or after BEAM loss, is not automatic. Jido has no recovery scanner. Your application must keep the list of Agents and call `Jido.activate_agent/4` or `Jido.thaw/4`.
- After a BEAM loss, a Turn resumes when its Agent activates. If you never activate that Agent, its Turn never finishes and its deadline has no effect.

## Work that can repeat

A step's result is saved after the step finishes. A crash between the external call and that save means the Action runs again, so a durable Flow gives at-least-once execution of each interrupted step. Earlier confirmed steps do not run again.

Jido cannot make external work exactly once. Use one of these patterns:

- **Reuse an operation ID.** Create the ID in an earlier step, so it is saved before the external call. Then the repeated call sends the same ID, and a provider that records IDs can treat it as a repeat.
- **Stop for a person.** If a provider cannot deduplicate, have the Flow commit a state such as `needs_attention` and send no call. Reconciling work already sent is your application's job.

Each step in the next example is a separate recovery boundary. The code runs the Action twice to stand in for recovery. A real provider must keep its records across its own failures.

```elixir
defmodule RecoveryLimitsGuide.Provider do
  # Stands in for an external service that records operation IDs.
  def start, do: :ets.new(__MODULE__, [:named_table, :public])

  def publish(operation_id, report) do
    case :ets.insert_new(__MODULE__, {operation_id, report}) do
      true -> :ok
      false -> if :ets.lookup(__MODULE__, operation_id) == [{operation_id, report}], do: :ok, else: {:error, :different_data}
    end
  end
end

defmodule RecoveryLimitsGuide.Publish do
  use Jido.Action,
    name: "recovery_limits_publish",
    schema: Jido.Joi.object(%{operation_id: Jido.Joi.string(), report: Jido.Joi.string()})

  @impl Jido.Action
  def run(%{operation_id: id, report: report}, _context) do
    case RecoveryLimitsGuide.Provider.publish(id, report) do
      :ok -> {:ok, %{operation_id: id, status: "published"}}
      {:error, reason} -> {:error, Jido.Error.execution_error("publish failed", %{reason: reason})}
    end
  end
end

defmodule RecoveryLimitsGuide.PublishReport do
  use Jido.Flow,
    name: "recovery_limits_publish_report",
    schema: Jido.Joi.object(%{report: Jido.Joi.string()})

  flow do
    # The AgentServer confirms this result before the next step starts.
    step "intent", report <- input(:report) do
      {:ok, %{operation_id: Jido.Id.uuid7(), report: report}}
    end

    step "publish",
      action: RecoveryLimitsGuide.Publish,
      params: %{operation_id: result("intent", :operation_id), report: result("intent", :report)}

    output result("publish")
  end
end

alias RecoveryLimitsGuide.{Provider, Publish, PublishReport}

Provider.start()

{:ok, %{status: "published"}} = Jido.Exec.run(Publish, %{operation_id: "op-1", report: "Q3"})
{:ok, %{status: "published"}} = Jido.Exec.run(Publish, %{operation_id: "op-1", report: "Q3"})
{:error, _reason} = Jido.Exec.run(Publish, %{operation_id: "op-1", report: "Q4"})

1 = :ets.info(Provider, :size)

{:ok, %{status: "published"}} = Jido.Exec.run(PublishReport, %{report: "Q3"})
2 = :ets.info(Provider, :size)
```

Cancelling a Turn stops local work. It does not undo a provider call that already finished.

## Effects after commit

Post-commit effects run after the commit that produced them, and Jido does not save their progress.

- A crash after the commit and before an effect finishes loses that effect. Recovery does not replay it.
- A saved completion does not replay post-commit hooks or effects when it restores.
- An uncertain commit runs no hooks or Directives, even if the write did land. Recovery reads that revision and does not run them later.

Use a Directive for work that may be lost, such as a notification. Use a Flow step before commit for work you must not lose, and accept that the step can repeat. [Runtime Effects](../agent-servers/runtime-directives-and-effects.md) has the delivery details.

An accepted Handoff has a similar boundary. A receipt with status `:accepted` proves that the predecessor committed, but not that its effects finished. On restore, Jido marks that receipt `:failed` and does not start the successor. A receipt with status `:released` resumes the successor.

## Requests are not deduplicated

- A repeated Signal is a new Turn, even after a crash and with the same Signal ID.
- The record keeps only the latest Turn receipt. It is not a ledger of past Turns.
- Guard repeats in your domain state, or check status and state after recovery before you resend.

## Code must stay compatible

- A pending Turn resumes only on matching Flow and Action code. Otherwise the activation stops with `:changed_reference`.
- A saved Agent restores only on matching referenced modules. Otherwise it stops with `:changed_reference` or `:unavailable_reference`.
- `Jido.Persistence.upgrade_agent/5` refuses a nonterminal Turn. Settle Turns before you deploy. See [Checkpoints and Upgrades](checkpoints-and-data-upgrades.md).

## Time limits

| Setting or value | Default | Behavior across recovery |
| --- | --- | --- |
| `turn_timeout:` | 60,000 ms | Saved as an absolute time. A restored Turn gets only the remaining time |
| `persistence_timeout:` | 5,000 ms | Bounds each required write. A later result counts as indeterminate |
| Flow timer in a wait | Set by the Flow | Saved as an absolute deadline. It can pass during downtime |

The absolute times use the system clock, so a large clock change moves them. A Turn past its deadline fails with a terminal receipt when it restores, and it runs no more steps.

## Waits

- Delivering a Signal before its wait opens returns `{:error, :not_waiting}`. There is no early-input mailbox, so retry.
- Jido keeps at most 1,024 accepted inputs for one execution. Beyond that, delivery fails with an `:input_limit` reason.
- Your application owns delivery and authorization of wait Signals.

[Flow Waits](../flow-runtime/flow-waits.md) covers the rest.

## Several writers

Compare-and-swap protects each record, but Jido has no cluster writer lease. Two activations of one Ref on different nodes can both run until one fails a write. The loser can already have called an external system. Use one active node per Ref, through your deployment or a placement layer. Each adapter's documentation states who can share it. `Jido.Persistence.File`, for example, requires one owning BEAM.

## Scope of a save

A record is one Agent. There is no atomic save across several Agents. See [Durable Topology](durable-topology.md).

## Next steps

- [Shutdown and Recovery](../operations/shutdown-and-recovery.md) plans application restarts.
- [Durable Turns and Flows](durable-turns-and-flows.livemd) shows recovery running.
- [Revisions and Conflicts](durable-revisions-and-conflicts.md) explains failed writes.
