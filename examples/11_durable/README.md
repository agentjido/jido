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
| [11_06 Durable Wait](11_06_durable_wait/README.md) | Implemented | Restore one suspended approval Flow with the same wait and deadline. |
| [11_07 External Uncertainty](11_07_external_uncertainty/README.md) | Implemented | Repeat an interrupted provider call with the same operation ID. |

Numbers stay stable. The seven implemented lessons have runnable source and behavior tests.

## Proposed lessons

Design work and test plans live under [proposals/](proposals/README.md). They
have no executable source and do not count as example coverage. IDs remain
stable. See the [integration checklist](proposals/flow-control/INTEGRATION.md)
for remaining API gates and proof order.

The supported Signal, timer, selection, and suspension path is consolidated in
11_06. Plans 11_08–11_12 retain design history and remaining early-input,
clock-policy, and long-duration questions. They do not require five duplicate
lessons. The proposal index also records topology waits, compatibility,
rollover, retry recovery, receipts, composed recovery, and failed-work policy.

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
recovery. Approval waits in `11_06` keep one durable Turn open and release its Runic Worker.
Hibernation retains the wait and deadline; thaw restores the same Turn. Flow and Action code must remain compatible while work is pending.

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
are required. See the [lifecycle guide](../../guides/agent-activation-control.md) and
[Core tests](../../test/contract/jido.agent_server/durable_turn/runtime_test.exs).

Previous: [Persistence](../10_persistence/README.md) | Next: [Saved Agent State](11_01_saved_agent/README.md)
