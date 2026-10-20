# Durable Flow integration

**Status: production wait transitions and durable AgentServer input are implemented.**
Action provides `Jido.Exec.Waits` for request inspection, matching, and native
wait completion. `Jido.AgentServer.DurableTurn.WaitHost` owns input receipts, duplicate IDs,
retention limits, clock delivery, and portability checks. AgentServer owns
persistence, Signal acceptance, Worker release, and restore.
Example 11_06 uses one suspended Flow. Normal Exec still rejects waits.

The implementation extends Action revision `63268a6f` and Jido revision
`7f4b8060`, with Runic revision `3bff1436`. Keep the sibling path dependencies
for local integration. Action and Jido changes must be released together before
this example can use published packages.

The host accepts input only for open wait IDs. It saves acceptance with the
native graph before acknowledgement, then saves selection before it resumes
Runic. It uses compare-and-swap and stops on a storage error. Unknown outcomes
require authoritative restore. No downstream Action runs inside the host.

The Worker stops after its confirmed waiting checkpoint. The AgentServer keeps
the serial Turn open. Hibernation saves the Turn receipt and retains the graph;
thaw restores the same wait and UTC deadline without repeating completed work.
The Turn timeout remains in force. Use a suitable timeout or `:infinity`.

Early input buffering, native wait-aware managed Exec, new-Turn handoff,
retry deadline recovery, Map/Iterate Flow bodies, history compaction, and
cluster ownership remain separate work. The README-only proposals below are
not promoted by this integration.

## Dependency source

Jido already uses the sibling V3 checkout in `mix.exs`:

```elixir
{:jido_action, path: "../jido_action", override: true}
```

Keep this declaration for local work. At integration time record the exact Action and Runic revisions
and any uncommitted upstream changes in the work report. Test results from an
unfinished checkout are provisional.

A GitHub source is an alternative once the patch has a verified commit. Replace
only the Action dependency with this form; the ref below is a placeholder:

```elixir
{:jido_action,
 git: "https://github.com/agentjido/jido_action.git",
 ref: "<verified-commit-sha>",
 override: true}
```

Do not select an unverified branch or add an environment-variable dependency
selector. Jido also uses a sibling Runic checkout. Confirm that it satisfies the
patched Action dependency; do not change that source or mix V2 packages into this
work without a concrete integration need. After a source/ref change, run
`mix deps.get`, compile, and test in Jido. Keep dependency and lock changes
explicit. The production wait host uses these local dependencies.

## Upstream contract review

Complete these checks from the patched source, public docs, and tests. Record
actual module/function names and output shapes in this document at integration
time. Issue text and old sketches are not authoritative API definitions.

- [x] Canonical timer, event wait, and selection definitions; equivalent DSL,
      map, and Codec forms; stored definition version handling.
- [ ] Execution-host setup and capability validation. Unsupported controls fail
      before an Action starts, including controls in composed targets.
- [ ] Execution status that distinguishes runnable, active, waiting, retrying,
      terminal success, and terminal failure. Record the supported subset.
- [ ] Stable wait identity, component path, and occurrence identity.
- [ ] Event acceptance/resolution interface and portable input/output schemas.
      Define which layer owns buffering, duplicate IDs, ordering, and selection.
- [ ] Timer deadline and clock contract; selected result and losing-wait cleanup.
- [ ] Checkpoint/restore and resource release APIs. Saved data must contain no
      PIDs, references, timer handles, runtime callbacks, or credentials.
- [ ] Cancellation and stale event/wake behavior.
- [ ] Retry attempt budget and next retry deadline across recovery.
- [ ] Explicit handoff result for a new Turn, if included. Ordinary Dispatch
      must keep its current same-execution meaning.
- [ ] Supported combinations of waits with Map, Iterate, nested Flow, and Dispatch.

Confirmed upstream limits: normal `Jido.Exec.run/4` and `start/6` return
`details.reason: :unsupported_host` and `capability: :waits`. Timer, event,
selection, nested Flow, and Dispatch recovery have test-driver evidence.
Map and Iterate do not accept waiting Flow bodies. The production transition API does not include Signal transport. AgentServer
provides addressed input and releases stopped Workers. Saved input and resolution
counts are bounded; there is no graph-history compaction or byte limit. Terminal handoff is a public `{:handoff, instruction, effects}` result;
AgentServer still needs atomic successor acceptance and queue-order tests.
The open checklist items require production contracts and consumer evidence.

Do not infer that all issues ship together. Implement only the examples whose
upstream capability and core contract are ready. Record missing support as a
gap; do not add silent fallbacks, fake host implementations, or skipped tests.

## Core integration boundary

Use the existing AgentServer `gen_statem`; add no coordinator process, chain
process, Plugin, or second Flow scheduler. Keep chain transitions as small pure
functions over saved runtime data outside Agent domain state. Keep pending work
bounded. OTP events coordinate live work; saved records establish recovery.

The current integration is in
[`DurableTurn`](../../../../lib/jido/agent_server/durable_turn.ex) and
[`AgentServer`](../../../../lib/jido/agent_server.ex). Review these seams first:

- `DurableTurn.advance/2` distinguishes a saved pending wait from completion.
  Runic still owns runnable readiness and execution policy.
- Reuse the existing confirmed checkpoint boundary before the next step. Resolve
  uncertain storage replies before dispatch, consumption, or successor acceptance.
- Translate a Jido Signal through `AgentServer.deliver_wait/4`. It bypasses
  ordinary postponed Turns while Agent state writes stay serial.
- Save accepted input before acknowledgement. Save consumption and the selected
  result before downstream work. Define overflow, duplicate, conflict, and expiry.
- Save UTC deadlines; reconstruct local timers. Do not persist OTP event queues.
  Do not use `next_event` as a FIFO tail insertion for successor Turns.
- Preserve cancellation and reads while waiting. Runner release does not release
  the Agent's serial write slot. Agree pending-Turn deactivation before 11_11.
- Directives remain post-commit effects. Settle request-and-wait before 11_13;
  do not use raw messages or a test callback to bypass the missing contract.
- New-Turn handoff commits Agent state, predecessor completion, successor
  acceptance/order, and chain metadata together. One-key atomic storage needs
  those values in the same record unless a separate recovery protocol is agreed.
  The successor joins the tail, uses current state at execution, and has a new
  Turn timeout. Preserve an optional absolute chain deadline. See 11_15.
- A temporary wake notification can be lost: restore must find accepted work
  from saved data. Chain cancellation must prevent later successor execution.
- Keep ordinary caller handles and queued Signals non-durable unless a separate
  acceptance contract explicitly changes that behavior.

## Example implementation order

Numbers and navigation stay stable. This is dependency order, not renumbering.
All 11_08–11_19 lessons remain README-only plans until implemented and tested.

| Stage | Lessons | First required proof |
| --- | --- | --- |
| Baseline | 11_01–11_07 | Existing state, step, completion, and external uncertainty contracts remain green |
| Event input | [11_08](../11_08_flow_signal_wait/README.md) | Step 6 waits; early/duplicate input and restart do not repeat steps 1–5 |
| Time and selection | [11_09](../11_09_flow_timer/README.md), [11_10](../11_10_signal_selection/README.md) | Saved deadline; one saved winner; no losing wait remains |
| Lifetime | [11_11](../11_11_suspended_activation/README.md), [11_12](../11_12_ninety_day_flow/README.md), [11_16](../11_16_retry_recovery/README.md) | Release resources; advance controlled time; retain retry budget |
| Communication and compatibility | [11_13](../11_13_topology_wait/README.md), [11_14](../11_14_recovery_compatibility/README.md) | Public request/reply boundary and compatible-code restore |
| Receipts and handoff | [11_17](../11_17_turn_receipts/README.md), [11_15](../11_15_execution_rollover/README.md) | Reconnect to chain result; atomic new-Turn acceptance and fair order |
| Composition and failure | [11_18](../11_18_composed_recovery/README.md), [11_19](../11_19_failed_work_recovery/README.md) | Occurrence identity, descendant cancellation, inspectable failed work |

## Proof and promotion rules

Write core regressions in `test/jido/agent_server/` before runtime changes. For
each saved transition cover rejection before write, confirmed write, lost reply,
process loss, cancellation, and stale replay where applicable. Keep detailed
fault matrices in core tests. The numbered example shows one main public use
and one important failure/recovery case, not a copied matrix.

Use static schemas, public AgentServer APIs, memory/ETS, controlled clocks, and
explicit barriers. Keep barriers and raw process messages in test support.
Start storage owners before the Jido tree. Reuse existing example support only
when it represents the same contract. Do not make one numbered example depend
on another example's private support. No real 30-day waits and no test retries.

When a lesson is ready, add its source and matching `:example` test, replace
proposed syntax with the verified API, add an exact run command, update its
status and the coverage register, and verify cleanup. Do not count README plans
as executable coverage. Keep 11_06 focused on one approval Flow. The 11_08 proposal still needs its
full early-input and restart acceptance matrix before promotion.

## Checks when integration starts

Test the lower-level Action package first from its own checkout. Then run in
Jido:

```sh
mix deps.get
mix format --check-formatted
MIX_ENV=test mix compile --warnings-as-errors
mix test test/jido/agent_server --seed 0 --warnings-as-errors
mix test test/examples/11_durable --include example --seed 0 --warnings-as-errors
mix test.examples --seed 0
mix quality
```

Run each new example test alone before the section suite. Add lifecycle,
persistence, authoring, and peer checks when the change affects those contracts.
Keep the existing BEAM-loss proof on retained storage. ETS tests do not prove
recovery after BEAM or storage loss. Review any failure against the verified
upstream contract before changing examples. No hosted-product work is included.
