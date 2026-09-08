> Target seam design. This document is pending approval.

# Agent Server design

All requirements and decisions in this document are recommended targets. EARS
syntax does not mean that the user approved a requirement. Code defines current
behavior until an approved target is implemented.

## Scope and owner

- Owner: `Jido.AgentServer` and its private live activation state machine.
- In scope: standard OTP startup, one live state owner, Signal admission,
  serialization, active-Turn control, task and timer ownership, live commit
  coordination, Directive settlement, Plugin runtime links, child-effect
  coordination, inspection, hibernation, and process stop behavior.
- Out of scope: Agent value and construction meaning, route and candidate
  semantics, Plugin facet callback values, persistence records and CAS result
  meaning, Agent Ref fields, namespace binding, instance facade policy,
  placement and cluster ownership, transport, and application architecture.
- Adjacent owners: seams 01 and 02 own canonical Agent construction; seam 03
  owns stable identity; seam 04 owns candidate evaluation; seam 05 owns Plugin
  facets; seam 06 owns commit meaning; seam 07 owns storage semantics; seam 12
  owns public errors. Seams 09 and 10 own instance and topology policy.

## Model

One Agent Server is one replaceable activation of one logical Agent. It owns
the mutable OTP state for that activation. The Agent value remains immutable,
portable domain data. A PID or OTP name is a runtime handle, not durable
identity.

The recommended live sequence is:

```text
canonical Agent input or known identity
  -> restore and validate
  -> start Plugin runtimes and await readiness
  -> initial durable create, when required
  -> publish ready
  -> admit one source Signal
  -> use the seam-04 candidate-evaluation contract
  -> validate live Directive policy
  -> checkpoint and commit one complete Agent
  -> reply with commit result
  -> handle Directives in order
  -> publish one terminal Outcome
```

The public status compatibility map has these phases:

| Phase | Meaning | Signal behavior |
| --- | --- | --- |
| `initializing` | Restore, Plugin startup, readiness, and initial durability | Postpone within admission rules |
| `idle` | No active Turn | Admit one Signal |
| `admitting` | Live Plugin admission is running | Postpone within admission rules |
| `running` | Candidate evaluation or synchronous commit work is active | Postpone within admission rules |
| `directing` | Post-commit Directive settlement is active | Postpone within admission rules |

Private state can use more detail. It must not change public result meaning.
The current Outcome stage compatibility set is `prepare`, `execute`,
`finalize`, `commit`, and `directive`. Seam 13 can propose a staged observation
migration. Private seam-04 evaluator stages are not public Server phases.

There is no general degraded phase. A Plugin runtime can be temporarily
`restarting`. During this condition the Server keeps inspection and control
responsive, does not substitute another handler, and stops if replacement
readiness fails. A Server that loses persistence write authority does not run
in a degraded writer mode. It stops before another Turn.

## Requirements

Each requirement is a pending target. Its acceptance state is in
[alignment.md](alignment.md).

### Server role and OTP boundary

`SRV-REQ-001`: While one Agent activation is live, the Agent Server shall be
the only owner of its authoritative Agent snapshot and state version.

`SRV-REQ-002`: While one Agent activation is live, the Agent Server shall have
no more than one active Turn.

`SRV-REQ-003`: The Agent Server shall keep tasks, PIDs, monitors, timers,
callers, Plugin runtime handles, and child handles outside the Agent value and
every checkpoint.

`SRV-REQ-004`: When a developer starts an Agent Server directly or under a
supervisor, the Agent Server shall use standard OTP start and child-spec
contracts.

### Startup and identity resolution

`SRV-REQ-005`: When Agent Server startup receives an Agent module or neutral
definition, the Agent Server shall construct an instance through the canonical
Agent construction boundary.

`SRV-REQ-006`: When Agent Server startup receives an Agent instance, the Agent
Server shall reject Server options that replace that instance's identity or
initial state.

`SRV-REQ-007`: When startup receives a resolved Agent identity, the Agent
Server shall treat its PID or OTP name as a replaceable runtime handle.

`SRV-REQ-008`: Where persistence is configured for restore, when the Agent
Server starts, it shall load and validate the latest active record before it
admits a Turn.

`SRV-REQ-009`: Where persistence is configured for a new activation, when
Plugin runtimes become ready, the Agent Server shall confirm a create-only
state-version-zero write before it reports readiness.

`SRV-REQ-010`: If restore, Agent validation, Plugin startup, Plugin readiness,
or the initial durable write fails, then the Agent Server shall fail startup
without reporting readiness.

`SRV-REQ-011`: If startup fails after a provisional Plugin runtime starts,
then the Agent Server shall stop every provisional Plugin runtime from that
startup.

### Command and Signal entry points

`SRV-REQ-012`: When `call/3` receives a valid Signal, the Agent Server shall
return the committed Agent or a defined pre-commit error.

`SRV-REQ-013`: When a successful `call/3` returns, the Agent Server shall not
claim that post-commit Directive settlement or external business work is
complete.

`SRV-REQ-014`: When `cast/2` returns `:ok`, the Agent Server shall mean only
that the Signal message was sent to the resolved Server handle.

`SRV-REQ-015`: When `send_request/3` and `receive_response/2` are used, the
Agent Server shall preserve the documented OTP asynchronous-request envelope.

`SRV-REQ-016`: If a caller wait limit expires after Turn work starts, then the
Agent Server shall continue the Turn unless an explicit cancellation succeeds.

`SRV-REQ-017`: While no approved migration removes the documented PID/name
operations, the Agent Server shall keep those operations supported beside any
Ref-first instance facade.

### Queueing and serialization

`SRV-REQ-018`: While a Turn is active, when another Signal reaches the state
machine, the Agent Server shall postpone that Signal through OTP.

`SRV-REQ-019`: When postponed Signals become admissible, the Agent Server shall
process their OTP delivery order without a second private Signal queue.

`SRV-REQ-020`: Where `max_postponed_signals` is finite, the Agent Server shall
limit only postponed events that have reached its state-machine callback.

`SRV-REQ-021`: If a synchronous Signal reaches a full postponed-event limit,
then the Agent Server shall reject it with the approved overload error.

`SRV-REQ-022`: If an asynchronous cast reaches a full postponed-event limit,
then the Agent Server shall drop it and emit bounded failure observation.

`SRV-REQ-023`: If live admission, executable work, or Directive work makes a
synchronous call to the same activation, then the Agent Server shall reject
the call with the owner-defined reentry error.

### Turn execution and control

`SRV-REQ-024`: When live admission runs, the Agent Server shall preserve the
unchanged source Signal without selecting or replacing an executable.

`SRV-REQ-025`: When more than one Agent Server Plugin facet admits a Signal,
the Agent Server shall call them serially in Plugin declaration order.

`SRV-REQ-026`: When admission accepts a Signal, the Agent Server shall invoke
the seam-04 candidate-evaluation boundary with that source Signal and bounded
Turn context.

`SRV-REQ-027`: When the Turn evaluator selects an executable, the Agent Server
shall invoke `Jido.Exec` with that exact executable for the Turn.

`SRV-REQ-028`: Where a Server-wide Turn limit is configured, when cancellable
pre-commit work starts, the Agent Server shall apply that one limit through
admission and candidate evaluation until commit begins.

`SRV-REQ-029`: If the Server-wide Turn limit expires before commit, then the
Agent Server shall terminate owned evaluation work, reject late results, keep
the committed snapshot, and publish one timed-out result.

`SRV-REQ-030`: When cancellation targets the active admission or evaluation
work before commit, the Agent Server shall cancel only that Turn and keep the
committed snapshot.

`SRV-REQ-031`: If cancellation arrives after commit begins or during Directive
settlement, then the Agent Server shall reject cancellation with the approved
too-late result.

### Commit and persistence recovery

`SRV-REQ-032`: When candidate evaluation succeeds, the Agent Server shall
accept only one complete validated Agent and one ordered Directive list for
commit.

`SRV-REQ-033`: When a live Directive batch has invalid ownership, size,
terminal position, or dispatch data, the Agent Server shall reject it before
checkpoint work starts.

`SRV-REQ-034`: When a nonpersistent Turn commits in a named Jido instance, the
Agent Server shall write the in-instance runtime checkpoint before it replaces
the live Agent.

`SRV-REQ-035`: Where persistence is configured, when a Turn commits, the Agent
Server shall receive confirmed CAS success before it replaces the live Agent.

`SRV-REQ-036`: When a live commit succeeds, the Agent Server shall replace the
complete Agent snapshot and increase the state version by exactly one.

`SRV-REQ-037`: When a live commit succeeds, the Agent Server shall make the
new Agent and state version authoritative before it replies success or starts
a Directive.

`SRV-REQ-038`: If a required checkpoint write is not confirmed, then the Agent
Server shall preserve the prior Agent and state version without starting a
Directive from that Turn.

`SRV-REQ-039`: If a required persistence write returns any error or
indeterminate result, then the Agent Server shall stop before it admits another
Turn.

`SRV-REQ-040`: Where a nonpersistent Server runs in a named Jido instance,
when that Server restarts abnormally, the Agent Server shall restore the latest
in-instance runtime checkpoint and matching state version.

### Plugin facets and runtime lifecycle

`SRV-REQ-041`: Where a Plugin Agent Server facet declares a runtime, when the
Agent Server starts it, the Agent Server shall own its runtime root and wait
for readiness before it reports Agent readiness.

`SRV-REQ-042`: When the Agent Server starts or replaces a Plugin runtime, it
shall provide one immutable input with the latest committed owned Plugin state
and matching Agent state version.

`SRV-REQ-043`: While a required Plugin runtime is restarting, the Agent Server
shall keep inspection and control calls responsive.

`SRV-REQ-044`: If a required Plugin runtime is unavailable, then the Agent
Server shall not substitute a process-free handler for that runtime.

`SRV-REQ-045`: If replacement Plugin readiness fails or reaches its readiness
limit, then the Agent Server shall stop the activation and the unready runtime
generation.

`SRV-REQ-046`: When a Plugin runtime requests an Agent state change, the Agent
Server shall accept that request only as a later Signal through the public
Agent mailbox boundary.

### Directive, child, and effect handling

`SRV-REQ-047`: When a committed Turn has Directives, the Agent Server shall
handle them serially in returned list order.

`SRV-REQ-048`: If one Directive fails, exits, or reaches its operation limit,
then the Agent Server shall stop that batch and skip every later Directive.

`SRV-REQ-049`: If post-commit Directive handling fails, then the Agent Server
shall preserve the committed Agent and state version.

`SRV-REQ-050`: When a built-in child Directive starts, adopts, addresses, or
stops a child, the Agent Server shall keep the child handle and monitor data in
private runtime state.

`SRV-REQ-051`: When an owned child exits, the Agent Server shall report that
change to Agent behavior as a later Signal and not as an in-place Agent state
change.

`SRV-REQ-052`: If a child start or remote stop result is indeterminate, then
the Agent Server shall report one indeterminate result that neither confirms
completion nor falls back locally.

`SRV-REQ-053`: If an Agent Server exits during an ordinary Directive batch,
then a later activation shall not replay that transient batch from an Agent
checkpoint.

### Stop, degraded conditions, and outcomes

`SRV-REQ-054`: When hibernation is requested while the Agent Server is idle,
the Agent Server shall preserve the current active record or checkpoint before
it stops.

`SRV-REQ-055`: While admission, evaluation, or Directive settlement is active,
when hibernation is requested, the Agent Server shall wait until the activation
returns to idle before it performs hibernation.

`SRV-REQ-056`: When a controlled stop begins, the Agent Server shall terminate
owned evaluation, admission, Directive, readiness, error-policy, and Plugin
runtime work before termination completes.

`SRV-REQ-057`: If Jido detects a broken Agent Server invariant, then the Agent
Server shall exit through OTP instead of converting it to an ordinary Agent
error.

`SRV-REQ-058`: When a Turn reaches an observed terminal point, the Agent
Server shall create one validated Turn Outcome whose commit and Directive
counts match the completed work.

`SRV-REQ-059`: If an Agent Server exits before it creates a terminal Turn
Outcome, then a later activation shall not reconstruct settlement from the
checkpoint alone.

### Code revision and strict ownership limits

`SRV-REQ-060`: Where a saved definition revision is present, if Persistence
reports a module or definition mismatch, then the Agent Server shall fail
startup before readiness and Turn admission.

`SRV-REQ-061`: When the Agent Server invokes `Jido.Exec`, it shall use the
executable selected for that Turn with the executable code loaded at invocation.

`SRV-REQ-062`: The Agent Server shall not define Agent construction, route
selection, candidate assembly, Plugin facet data, or persistence record
meaning.

`SRV-REQ-063`: The Agent Server shall not bind an Agent namespace, resolve a
stable Agent Ref, select process placement, or grant cluster write authority.

`SRV-REQ-064`: The Agent Server shall not claim durable replay for ordinary
Directives, rollback for executable external I/O, or exactly-once external
effects.

`SRV-REQ-065`: While current public controls remain supported, the Agent Server
shall expose no supported external access to its private state or private
messages.

## Public contract

### Supported compatibility entries

The current public roles remain supported until an approved migration proves a
replacement:

| Role | Entries | Result meaning |
| --- | --- | --- |
| OTP startup | `start_link/1`, `start/1`, `child_spec/1` | Standard OTP or supervised-start result |
| Signal input | `call/3`, `cast/2`, `send_request/3`, `receive_response/2` | Commit result, best-effort send, or OTP request protocol |
| Turn control | `cancel/2`, `cancel_turn/3` | Active pre-commit cancellation or defined rejection |
| Inspection | `agent/2`, `plugin_state/3`, `status/2`, `snapshot/2`, `children/2`, `await_ready/2` | Current committed or bounded runtime view |
| Lifecycle | `stop/3`, `hibernate/2`, `attach/3`, `detach/3`, `touch/1` | Process and idle-lifecycle control |
| Local handles | `whereis/3`, `via_tuple/3`, `alive?/1` | Replaceable PID/name lookup and liveness |
| Debug | `set_debug/3`, `recent_events/3` | Bounded in-process diagnostic compatibility path |

The target does not require new `Status`, `Commit`, or Snapshot structs. Seam
12 requires the owner to document why compatibility maps and OTP controls
remain. Seam 13 owns any change to Outcome availability or observation data.

A Ref-first command and lifecycle facade is additive and belongs to seam 09.
That facade resolves identity and calls this runtime boundary. It cannot make
PID identity durable or remove current functions without a separate approved
migration.

### Time limits

The owner of each limit must stay clear:

| Limit | Scope |
| --- | --- |
| Caller wait or admission deadline | Caller wait and time spent postponed before admission |
| Server Turn limit | Live admission and candidate evaluation before commit |
| Readiness limit | One Plugin runtime readiness operation |
| Persistence operation limit | One storage operation, if seam 07 and seam 09 configure it |
| Directive limit | One post-commit Directive operation |
| Idle limit | Time with no active Turn and no attachment |

A persistence write operation limit is an indeterminate persistence result. It
is not a general Turn timeout. Exact option names and defaults remain open until
the owning seams approve them.

### Code revision

Agent definition revision is immutable Agent definition data. Persistence
checks it before startup. It is not the Agent state version, activation ID,
storage revision, or an Action or Flow code snapshot. V3 makes no guarantee
that a definition revision pins BEAM code during a Turn. A hot upgrade of
private Agent Server state has no current public migration contract. Any such
contract needs a separate state-shape, rollback, and in-flight-Turn design.

## Invariants

- `SRV-INV-001`: One activation has one live state owner and no more than one
  active Turn.
- `SRV-INV-002`: A candidate is never visible before the required checkpoint
  succeeds.
- `SRV-INV-003`: Directive work never starts before commit.
- `SRV-INV-004`: A post-commit failure never rolls back committed state.
- `SRV-INV-005`: Runtime handles never enter Agent or Plugin-owned state.
- `SRV-INV-006`: Loss of persistence write authority cannot become a degraded
  writer mode.
- `SRV-INV-007`: Agent identity, runtime location, activation identity, state
  version, definition revision, and storage revision remain separate values.
- `SRV-INV-008`: Agent Server policy does not become instance or topology
  policy.

## Downstream guarantees

These guarantees apply only after the related requirements are approved.

| Consumer seam | Guaranteed contract |
| --- | --- |
| 09 Jido instance | A resolved runtime handle has serialized command, control, inspection, and lifecycle behavior; Ref resolution stays instance-owned. |
| 10 Runtime topology | One activation owns live state; placement and cluster authority remain outside Agent Server. |
| 11 Topology control plane | Child effects use runtime contracts but do not define Topology reconciliation policy. |
| 13 Observability | Current phases, Outcome stages, commit point, settlement point, and interruption limits have explicit meanings. |
| 99 Delivery | Every Server requirement has one acceptance state and compatibility gate. |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `SRV-DEC-001` | Which direct Server APIs remain public? | Keep current documented PID/name operations until Ref-first replacement proof and a later approval. | No supported V3 runtime API disappears in this seam. |
| `SRV-DEC-002` | Which phases and Outcome stages remain public? | Keep the current five status phases and five Outcome stages as compatibility values. | Seam 13 can plan a later bounded projection without changing runtime first. |
| `SRV-DEC-003` | What does a Server-wide Turn limit cover? | Cover Plugin admission and all candidate evaluation before commit. | Cancellation and timeout use one pre-commit boundary. |
| `SRV-DEC-004` | What happens after a required persistence error? | Stop before another Turn for conflict, rejection, fault, timeout, or indeterminate result. | A stale activation cannot keep writing. |
| `SRV-DEC-005` | How does Plugin replacement appear? | Keep current `:restarting` child visibility; require one state-version bootstrap pair and stop on readiness failure. | Inspection stays responsive without adding a general degraded phase. |
| `SRV-DEC-006` | What can error policy change? | Keep current policies during migration, but prevent them from overriding authority, commit, and Directive atomicity. | Compatibility remains while safety decisions stay fixed. |
| `SRV-DEC-007` | Does definition revision pin executable code? | No. Use the code loaded when `Jido.Exec` invokes the selected executable. | Restore checks module meaning without promising a BEAM snapshot. |
| `SRV-DEC-008` | Is hot private-state upgrade in V3 scope? | Defer it until a separate migration and rollback contract exists. | This seam makes no unsupported live-upgrade claim. |
