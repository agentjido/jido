# Durable examples

One durable Flow is the current AgentServer Turn. Other state-changing Turns
wait. Reads, status, and cancellation remain available.

```elixir
{:ok, server} = Jido.start_agent(MyJido, ReportAgent,
  id: "report", persistence: :inherit)
:ok = Jido.AgentServer.await_ready(server)
Jido.AgentServer.call(server, request)
```

## Recovery rule

```text
save acceptance with Agent → run step → confirm checkpoint → run next step
Flow completes → save candidate Agent and completion together → release Turn
```

If steps 1–5 have confirmed saves and the Agent dies during step 6, recovery starts
step 6 again. It does not resume inside an Action. External I/O in that Action can
repeat. Runic owns graph progress; there is no second step counter.

## Learning order

| Example | Status | Proof |
| --- | --- | --- |
| [11_01 Saved Agent State](11_01_saved_agent/README.md) | Implemented | Restore a committed Agent after BEAM loss; no pending Flow. |
| [11_02 Saved Progress](11_02_saved_progress/README.md) | Implemented | AgentServer resumes step 6 after process loss; steps 1–5 do not repeat. |
| [11_03 VM Recovery](11_03_vm_recovery/README.md) | Implemented | Restore the same Turn in a fresh BEAM with a small DETS byte adapter. |
| [11_04 Accepted Work](11_04_accepted_work/README.md) | Implemented | A topology member runs and commits a durable report Turn. |
| [11_05 Saved Completion](11_05_saved_completion/README.md) | Implemented | Restore completion after a lost storage reply without repeated work. |
| [11_06 Durable Wait](11_06_durable_wait/README.md) | Implemented | Restore a saved approval wait between completed Flow Turns. |
| [11_07 External Uncertainty](11_07_external_uncertainty/README.md) | Implemented | Repeat an interrupted provider call with the same operation ID. |

Numbers stay stable. The seven implemented lessons have runnable source and behavior tests.

## Proposed lessons

These README-only spikes are explicitly requested design work. They are not
implemented examples or evidence of supported behavior. Start with the
[integration checklist](flow-control/INTEGRATION.md), then review the
[Flow control DSL proposal](flow-control/README.md). The checklist records
dependency selection, upstream API gates, core seams, and proof order.

| Example | Status | Planned proof |
| --- | --- | --- |
| [11_08 Flow Signal Wait](11_08_flow_signal_wait/README.md) | README proposal | Step 6 waits for an external event in the same ten-step Flow Turn. |
| [11_09 Flow Timer](11_09_flow_timer/README.md) | README proposal | A timer is a saved Flow control step, with no long-running Action. |
| [11_10 Signal Selection](11_10_signal_selection/README.md) | README proposal | Step 6 selects approval, rejection, or a 30-day timeout. |
| [11_11 Suspended Activation](11_11_suspended_activation/README.md) | README proposal | A waiting Flow releases execution resources and resumes after activation. |
| [11_12 Ninety-Day Flow](11_12_ninety_day_flow/README.md) | README proposal | A Flow runs across 90 days through several saved waits. |
| [11_13 Topology Wait](11_13_topology_wait/README.md) | README proposal | A topology member resumes a waiting Flow from another member’s Signal. |
| [11_14 Recovery Compatibility](11_14_recovery_compatibility/README.md) | README proposal | Pending work resumes only with a compatible execution definition. |
| [11_15 Execution Rollover](11_15_execution_rollover/README.md) | README proposal | Atomically finish one Turn and accept a new Turn in the same chain. |
| [11_16 Retry Recovery](11_16_retry_recovery/README.md) | README proposal | Keep retry limits and retry deadlines across AgentServer recovery. |
| [11_17 Turn Receipts](11_17_turn_receipts/README.md) | README proposal | Find accepted work and its final result after the original caller is lost. |
| [11_18 Composed Recovery](11_18_composed_recovery/README.md) | README proposal | Recover waits inside repeated and nested Flow components without identity collisions. |
| [11_19 Failed Work Recovery](11_19_failed_work_recovery/README.md) | README proposal | Inspect failed pending work and define a safe, explicit recovery decision. |

## Ownership

| Owner | Responsibility |
| --- | --- |
| OTP supervisor | Restart processes within the live BEAM. |
| AgentServer | Accept, checkpoint, restore, cancel, and commit the current Turn. |
| Agent | Hold committed domain state. |
| Runic | Hold and restore the Flow graph; execute runnable work. |
| Application | Own storage, retain compatible code, and activate known roots after BEAM loss. |

`11_02` uses the existing ETS persistence adapter. `11_03` starts its DETS owner
before Jido with `:rest_for_one`. `11_04` uses the File adapter. All use the same
Core checkpoint path. Example callers do not drive Runic or confirm checkpoints.
Test barriers are confined to test support.

## Limits

Persistence enables Flow recovery. Direct Actions remain
ordinary Turns. Caller handles and queued Signals do not survive a crash. A
repeated Signal is a new Turn, not a deduplicated request. The Turn timeout survives
recovery. Approval waits in `11_06` are Agent state between completed Turns;
they do not hold a Flow open. Flow and Action code must remain compatible while work is pending.

Completion commits Agent state and the terminal receipt together. Post-commit
hooks and effects are not replayed. Cancellation saves its terminal receipt before
stopping work. Normal stop retains pending work. Hibernation uses the existing
drain or cancel policy.

Topology members save independent records and retain stable slot identities.
A root snapshot is not an atomic family snapshot. There is no cluster writer
lease, recovery scanner, automatic graph record collection, or exactly-once I/O.
These examples prove process and BEAM loss with retained local storage. They do
not prove power-loss or storage-loss recovery. Parallel, nested, Map, and Iterate
Flows need separate recovery evidence before wider claims.

## Run it

```sh
mix test test/examples/11_durable --include example --seed 0 --warnings-as-errors
```

Child BEAM tests need local sockets and `kill`. No credentials or external service
are required. See the [lifecycle guide](../../guides/agent-server-lifecycle.md) and
[Core tests](../../test/jido/agent_server/durable_turn_test.exs).

Previous: [Persistence](../10_persistence/README.md) | Next: [Saved Agent State](11_01_saved_agent/README.md)
