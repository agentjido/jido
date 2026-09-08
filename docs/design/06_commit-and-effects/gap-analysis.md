# Commit and effects gap analysis

> Review report. This document is pending approval.

## Scope and owner

This report reviews only the commit-and-effects seam. The seam owns these
subjects:

- The change from a candidate Agent value to live Agent state.
- The order of state validation, persistence, caller reply, Directive dispatch,
  and Turn settlement.
- The durability boundary for Agent and Plugin state.
- The failure meaning before commit and after commit.
- The boundary between transient Directives and explicit recoverable work.

`Jido.AgentServer` owns the live commit and settlement sequence.
`Jido.Agent.Command.Runner` owns candidate and Directive validation.
`Jido.Persistence` owns the current checkpoint record and compare-and-swap
write. Plugins and applications own recoverable effect protocols.

This report uses `lib/` as the source of truth for implemented behavior. The
REC-01 example and its tests are evidence for one application pattern. They are
not a core implementation because production builds compile `lib/` only
(`mix.exs:166-171`).

## Implemented baseline

The following list states current facts.

1. `Jido.Agent.cmd/3` returns an immutable candidate and a Directive list. It
   does not own a process or live state (`lib/jido/agent.ex:1-17`).
2. Finalization normalizes the executable result, protects Plugin-owned state,
   validates every Directive, applies Plugin state reducers, and validates the
   complete Agent transition (`lib/jido/agent/command/runner.ex:120-133`,
   `lib/jido/agent/command/runner.ex:229-260`).
3. The Server validates the batch limits and Signal dispatch options before the
   commit (`lib/jido/agent_server.ex:1485-1507`,
   `lib/jido/agent_server.ex:1639-1644`).
4. A commit calculates one new revision. The Server writes a runtime checkpoint
   or a durable record before the Server replaces its live Agent and revision
   (`lib/jido/agent_server.ex:1493-1527`,
   `lib/jido/agent_server.ex:2907-2929`).
5. The Server replies to a synchronous caller at the commit boundary. The
   Server then runs Directives in list order. The Server does not admit the next
   Turn until the Directive batch stops (`lib/jido/agent_server.ex:1529-1545`,
   `lib/jido/agent_server.ex:1225-1235`,
   `lib/jido/agent_server.ex:1853-1875`).
6. Plugin Directive work runs in a supervised task. Each entry has its own
   timeout. A failed entry stops the rest of the batch and creates a committed
   failed Outcome (`lib/jido/agent_server.ex:1785-1835`,
   `lib/jido/agent_server.ex:1725-1756`).
7. Turn settlement happens after the last Directive, or after the first
   Directive failure. Settlement clears the active Turn and emits terminal
   telemetry (`lib/jido/agent_server.ex:1853-1857`,
   `lib/jido/agent_server.ex:2618-2638`).
8. A known persistence failure keeps the prior live state. An uncertain write
   also stops the current Server before later work can run
   (`lib/jido/agent_server.ex:1548-1584`). The adapter contract defines an
   exception or invalid result as uncertain (`lib/jido/persistence/adapter.ex:23-38`).
9. There is no universal core Directive outbox. The REC-01 example stores
   pending and completed IDs in Plugin-owned Agent state and uses a Directive as
   a wake-up only
   (`examples/04_runtime/04_11_recoverable_delivery/recoverable_delivery.ex:17-85`).

## Aligned contracts

The following design statements align with current code.

- **Candidate isolation:** Direct evaluation does not commit live state and does
  not dispatch Directives. External I/O during Action or Flow execution cannot
  be rolled back. The public Agent and AgentServer module documents state this
  rule (`lib/jido/agent.ex:9-17`, `lib/jido/agent_server.ex:12-15`).
- **Complete pre-commit validation:** The runner validates Directive ownership
  and contents before Plugin state reduction and final Agent transition. The
  Server adds whole-batch checks before persistence
  (`lib/jido/agent/command/runner.ex:120-133`,
  `lib/jido/agent/command/runner.ex:229-260`,
  `lib/jido/agent_server.ex:1639-1644`).
- **Write before live state:** The durable compare-and-swap write uses the
  current revision as `:expected_revision`. Live state changes only after `:ok`
  (`lib/jido/agent_server.ex:1493-1527`,
  `lib/jido/agent_server.ex:2920-2929`).
- **One Turn, one revision:** Every successful Turn adds one revision, including
  an equal-state result. The Outcome validator requires the new revision to be
  exactly the old revision plus one (`lib/jido/agent_server.ex:1493-1496`,
  `lib/jido/agent/turn/outcome.ex:109-124`).
- **Commit before effect:** The caller receives the committed Agent before the
  Directive batch settles. Directive dispatch uses the committed revision and
  Plugin state (`lib/jido/agent_server.ex:1529-1545`,
  `lib/jido/agent_server.ex:1793-1811`).
- **No rollback after dispatch failure:** A post-commit failure keeps the new
  revision. The Outcome records the failed index and the number of skipped
  entries (`lib/jido/agent_server/active_turn.ex:90-129`,
  `lib/jido/agent_server.ex:1725-1756`).
- **Explicit durable intent:** The default checkpoint stores the complete Agent
  state map. Plugin state reducers run before the Agent transition. Therefore,
  an application can commit business state and pending work in one checkpoint
  (`lib/jido/agent.ex:403-420`, `lib/jido/plugin.ex:826-855`).
- **Lost write authority for an uncertain result:** The Server sends no
  Directive and stops after an indeterminate save. Tests cover both an explicit
  indeterminate return and an exception after storage changed
  (`test/jido/persistence/indeterminate_write_test.exs:46-94`).

## Gaps

### Missing implementation

#### MI-1: A new persistent Agent is not durable before its first Turn

Current fact: When no record exists, startup can publish the supplied revision
zero Agent without a durable write. The first successful Turn, hibernate, or
clean stop creates the record. The adjacent persistence design records this
current limitation (`docs/design/07_persistence/persistence-adapters.md:217-241`).

Impact: A VM failure before the first write can lose the initial Agent and
Plugin state. Therefore, the sentence "Core restores committed Agent and Plugin
state" needs a revision-zero qualification.

Proposal: Add a confirmed revision-zero compare-and-swap write before a new
persistent Server becomes ready. Treat an uncertain startup write as lost write
authority.

#### MI-2: Recoverable delivery is a demonstrated pattern, not a shipped core
capability

Current fact: REC-01 is in `examples/`, and only development and test builds
compile that directory (`mix.exs:166-171`). Core supplies the state, Plugin,
checkpoint, and supervised runtime parts. Core does not supply a general work
record, receiver protocol, retry engine, or completion API.

Impact: The design can claim that core permits an explicit delivery capability.
The design must not claim that core provides one universal capability.

Proposal: Keep this ownership outside core. If Jido needs a reusable capability,
define it as a separate Plugin with its own delivery contract and tests.

### Design/code conflict

#### DC-1: The checkpoint inclusion statement is too strong for custom callbacks

Current fact: The default checkpoint stores the full Agent state, including
Plugin-owned fields (`lib/jido/agent.ex:403-420`). However, an Agent can replace
`checkpoint/2` and `restore/2`. Core only requires the custom checkpoint to be a
plain map. Core validates the restored Agent and module, but core does not prove
that the custom checkpoint preserved each Plugin-owned field
(`lib/jido/agent.ex:128-132`, `lib/jido/agent.ex:370-400`,
`lib/jido/agent.ex:509-551`).

Conflict: `commit-and-effects.md:91-93` says that the checkpoint includes Agent
and Plugin-owned state. `durability-guarantee.md:13-19` also states restoration
without a custom-callback condition.

Proposal: State that the default checkpoint includes complete Agent and Plugin
state. Require custom checkpoint and restore callbacks to preserve every state
field that participates in a durable effect protocol.

### Missing decision

#### MD-1: Define the public meaning of Turn settlement

Current fact: `AgentServer.call/3` returns after commit and before Directive
settlement (`lib/jido/agent_server.ex:160-178`,
`lib/jido/agent_server.ex:1529-1545`). The complete Outcome is available through
telemetry and internal event history. The normal call result contains no Turn ID
and no settlement handle.

Open decision: Decide whether settlement is only an observability term, or a
public synchronization contract. If applications must wait for settlement,
define a stable public operation that uses the Turn ID. If applications must not
wait, state that `call/3` confirms commit only and that telemetry is not a reply
channel.

#### MD-2: Define the outcome when the Server dies during ordinary Directive work

Current fact: The runtime checkpoint contains the committed Agent and revision,
but not the active Directive batch (`lib/jido/agent_server.ex:28-38`,
`lib/jido/agent_server/runtime_checkpoint.ex:1-45`). Ordinary Directives are not
replayed. A process death can also prevent creation of a terminal Turn Outcome.

Open decision: State whether this Turn has no observable settlement, or whether
activation must emit an indeterminate terminal record for the interrupted Turn.
Do not imply that recovery can reconstruct the transient batch.

#### MD-3: State the uncertainty rule for an ordinary Directive timeout

Current fact: The Server stops the Directive task at timeout, records one failed
entry, skips later entries, and applies the error policy
(`lib/jido/agent_server.ex:1012-1029`,
`lib/jido/agent_server.ex:1725-1756`). An external operation can still have
completed before the timeout result.

Open decision: State that `:timed_out` is a runtime settlement status. It is not
proof that the external effect did not occur. Applications need stable IDs and
duplicate handling when they retry timed-out work.

#### MD-4: Finish the policy for known persistence write failures

Current fact: An uncertain write always stops the Server. A known conflict or
known no-write error follows the configured error policy
(`lib/jido/agent_server.ex:1560-1568`). The seam design explicitly leaves the
stricter write-authority rule to the instance persistence work
(`durability-guarantee.md:55-59`).

Open decision: Keep the current distinction, or adopt the adjacent proposal that
all persistence write errors remove write authority. The commit seam and the
persistence seam must state the same rule.

### Missing verification

#### MV-1: No focused test proves loss of an ordinary batch during a Server crash

Existing tests prove post-commit dispatch failure, timeout, skipped entries, and
state retention (`test/jido/agent_server/directive_execution_test.exs:134-220`,
`test/jido/agent_server/directive_execution_test.exs:254-348`). No focused test
kills the Server during an ordinary Directive and proves the documented
non-replay behavior after restart.

Proposal: Add a test that commits a batch, blocks the first ordinary Directive,
kills the Server, restores the committed revision, and proves that core does not
replay the blocked or remaining entries.

#### MV-2: Custom checkpoints do not verify durable Plugin intent preservation

Existing checkpoint tests verify portability and identity. REC-01 uses the
default checkpoint. No seam test combines a custom Agent checkpoint with a
Plugin-owned pending work set.

Proposal: Add a test that either proves the required preservation rule or proves
that the documentation clearly assigns this duty to the custom Agent callbacks.

#### MV-3: Storage durability evidence is limited

REC-01 tests cover process loss, Plugin loss, known failed writes, duplicate
delivery, and later Turns (`test/jido/agent_server/effect_recovery_test.exs:88-209`).
The tests use one BEAM and the File adapter. They do not prove a power-loss
flush, a shared writer across nodes, or a safe result after an indeterminate
write.

Proposal: Keep these items as explicit non-guarantees. Add adapter-specific
integration tests only when an adapter claims stronger durability.

#### MV-4: Generic Directive list order has indirect coverage

The state machine consumes the list head first and stops after one failure
(`lib/jido/agent_server.ex:1225-1235`, `lib/jido/agent_server.ex:1725-1756`).
Current tests verify skip counts and Scheduler reducer order. A small generic
Plugin test does not directly record successful dispatch of three Directives in
the returned list order.

Proposal: Add one focused test for successful generic Plugin dispatch order and
one test for stop-at-first-failure order.

## Narrow dependency notes

- **Turn evaluation:** The commit seam depends on the runner to return one fully
  validated candidate and Directive list. Mid-command persistence and rollback
  are outside this seam (`docs/design/04_turn-evaluation/turn-evaluation.md:162-195`).
- **Persistence:** The current seam uses the binary adapter record and
  compare-and-swap revision. The proposed instance `Record`, lifecycle state,
  initial revision-zero write, and full authority model are not implemented by
  this seam (`docs/design/07_persistence/instance-persistence.md:8-14`,
  `docs/design/07_persistence/persistence-adapters.md:217-241`).
- **Agent Server:** Admission stays closed while a Turn is in `:directing`.
  Public `call/3` still returns at commit. These are different boundaries and
  must remain explicit (`lib/jido/agent_server.ex:5-10`,
  `lib/jido/agent_server.ex:160-178`).
- **Errors:** Persistence uncertainty and Directive timeout use different
  meanings. An uncertain persistence write removes write authority. A Directive
  timeout is post-commit and can have an external effect
  (`lib/jido/persistence/adapter.ex:23-38`,
  `lib/jido/agent_server.ex:1012-1029`).

## Ordered recommendations

The following items are proposals, in recommended order.

1. Correct the checkpoint wording. Limit the unconditional guarantee to the
   default checkpoint. State the duty of custom callbacks.
2. Lock the failure rule for known persistence errors with the persistence seam.
   Keep the separate, stricter rule for uncertain writes.
3. Define settlement as an internal observability boundary or add a public wait
   contract. Do not leave the term with two possible meanings.
4. Define crash-during-dispatch and Directive-timeout uncertainty in the seam
   document.
5. Implement the revision-zero durable creation boundary before broad durability
   claims.
6. Add the focused ordinary-Directive crash, order, and custom-checkpoint tests.
7. Keep the universal outbox removed. Keep retry, acknowledgement, retention,
   cancellation, and duplicate policy in each explicit capability.

## Evidence references

- Seam design: `docs/design/06_commit-and-effects/commit-and-effects.md:11-103`.
- Durability design: `docs/design/06_commit-and-effects/durability-guarantee.md:11-83`.
- Candidate finalization: `lib/jido/agent/command/runner.ex:120-133` and
  `lib/jido/agent/command/runner.ex:229-260`.
- Commit sequence: `lib/jido/agent_server.ex:1469-1545`.
- Directive sequence and failure: `lib/jido/agent_server.ex:1639-1875`.
- Settlement record: `lib/jido/agent_server/active_turn.ex:73-129` and
  `lib/jido/agent_server.ex:2618-2638`.
- Persistence boundary: `lib/jido/agent_server.ex:2874-2929` and
  `lib/jido/persistence.ex:59-99`.
- Uncertain write contract: `lib/jido/persistence/adapter.ex:23-38`.
- REC-01 implementation and evidence:
  `examples/04_runtime/04_11_recoverable_delivery/recoverable_delivery.ex:17-125`,
  `examples/04_runtime/04_11_recoverable_delivery/delivery_worker.ex:1-70`, and
  `test/jido/agent_server/effect_recovery_test.exs:42-209`.
- Post-commit failure evidence:
  `test/jido/agent_server/directive_execution_test.exs:27-43`,
  `test/jido/agent_server/directive_execution_test.exs:103-220`, and
  `test/jido/agent_server/directive_execution_test.exs:254-408`.

## Verification run

On 2026-09-08, the focused command completed with 32 passing tests:

```text
mix test test/jido/agent_server/directive_execution_test.exs \
  test/jido/agent_server/effect_recovery_test.exs \
  test/jido/persistence/indeterminate_write_test.exs
```
