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
| [11_05 Saved Completion](11_05_saved_completion/README.md) | Proposed lesson | Show the final-write failure window already covered by Core tests. |
| [11_06 Durable Wait](11_06_durable_wait/README.md) | Proposed | Define a saved wait without allowing concurrent state-changing Turns. |
| [11_07 External Uncertainty](11_07_external_uncertainty/README.md) | Proposed | Use an external operation ID when interrupted I/O can repeat. |

Numbers stay stable. Proposed folders have no skipped or placeholder tests.

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
recovery. Flow and Action code must remain compatible while work is pending.

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
