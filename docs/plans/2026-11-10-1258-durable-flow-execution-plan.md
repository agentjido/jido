---
title: Add host-neutral durable Flow execution
type: implementation-plan
date: 2026-11-10
last_reviewed: 2026-11-10
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Add host-neutral durable Flow execution

## Goal Capsule

- Objective: Add a small `Jido.Durable` API that runs and resumes persisted Flows without an Agent or AgentServer.
- Means: Reuse Jido Signal, Exec, Runic workflow history, Persistence Store adapters, and the existing durable wait machinery.
- Authority: Change and commit local files in the `jido` repository. Do not push.
- Stop conditions: Stop for a required new workflow language, journal product, scheduler, queue, package, or unresolved data-safety decision.
- Next executor: Jido implementation worker.

## Product Contract

### Summary

`Jido.Durable` is a host-neutral durable Flow execution boundary inside the `jido` package. A `Jido.Signal` is the external input. A durable host can resume a saved Flow, deliver Signals to saved waits, and schedule a later resume from the next saved wake time.

### Problem Frame

The current code has durable Runic checkpoints, wait receipts, and recovery policy, but the public durable path is embedded in AgentServer. `Jido.Exec` also exposes managed Runic execution, which makes the Runic escape hatch look like the primary durable API.

### Actors

- Application code that runs a durable Flow without an Agent.
- AgentServer, which composes durable Flow execution with Agent state and OTP lifecycle.
- A host capability, such as AgentServer Scheduler, that delivers cron occurrence Signals or wakes a timed wait.

### Requirements

- **R1:** Durable Flow execution must work without an Agent or AgentServer.
- **R2:** Initial and resumed external input must use `Jido.Signal`; duplicate wait delivery must be inert by Signal ID.
- **R3:** Durable execution must reuse `Jido.Flow`, `Jido.Exec`, Runic history, and `Jido.Persistence.Store` adapters. It must not add a second workflow language or a public Journal.
- **R4:** Durable execution must persist waits and expose the next wake time. A host can resume the execution for timers or deliver cron occurrence Signals.
- **R5:** AgentServer must use the same durable runtime primitives while it keeps Agent commit, process, wait-timer, and Scheduler integration policy.
- **R6:** The change must include basic unit tests and supported offline examples for direct completion, Signal wait resume, and host-driven scheduled resume.

### Key Flows

1. Start: Signal -> validate and bind Flow input -> persist durable metadata -> start or restore Runic workflow -> checkpoint each execution unit -> return terminal or waiting status.
2. Wait input: Signal plus wait ID -> save idempotent receipt -> acknowledge durable acceptance -> resume separately -> return terminal or waiting status.
3. Scheduled wake: host reads `next_wake_at` -> host calls resume at or after that time -> saved timer wait resolves.
4. Agent turn: AgentServer prepares a Flow and context -> calls durable runtime -> keeps Agent commit and lifecycle policy outside the durable core.

### Acceptance Examples

- A direct Flow completes through `Jido.Durable.start/4` and returns its normal Exec result.
- A Flow waits, survives worker suspension, accepts a matching Signal, and completes after resume.
- The same Signal ID and payload can be delivered twice without a second application.
- A timer wait returns `next_wake_at`; a host resume after that time completes it.
- Existing durable AgentServer tests continue to pass through the shared durable runtime.

### Success Criteria

- There is one public durable facade and one durable execution meaning.
- No new dependency, scheduler, queue, or public Journal is added.
- Focused Durable, Exec, AgentServer durable-turn, Persistence, and example tests pass.
- The package format, compile, and standard test gates pass.

### Scope Boundaries

In scope:

- `Jido.Durable`, a portable reference, a public status value, and internal runtime data.
- Persistent execution metadata needed for standalone resume.
- Existing Runic checkpoint and fact storage.
- Wait Signal acceptance and host-driven wake data.
- AgentServer delegation to the shared runtime.
- Offline examples and basic tests.

Out of scope:

- A `jido_durable` package.
- A public Journal or permanent audit-history contract.
- Worker queues, cron calculation, leases, dashboards, compensation, and child workflows.
- Exactly-once external effects.
- Removal of the advanced Runic escape hatch from `Jido.Exec`.

### Key Decisions

- `Jido.Durable` stays in the `jido` package.
- A Signal is the durable external input and its ID is the idempotency identity.
- The Runic workflow event stream and facts are the internal recovery history.
- `Jido.Persistence.Store` remains the only storage-adapter behavior.
- Cron is a host capability. The durable core exposes saved waits and wake time and accepts occurrence Signals.

### Rejected Alternatives

- Add `store:` to `Jido.Exec`: storage alone does not define Signal acceptance, wait recovery, or uncertain work.
- Add `Jido.Durable.Journal`: this creates retention, query, replay, and compatibility promises that are not required.
- Add a scheduler or queue to Durable: AgentServer Scheduler and application hosts already own delivery.
- Add a new package: explicitly excluded.

### Dependencies

- Existing Runic Runner and Store contracts.
- Existing `Jido.Persistence.Store` adapters and `Jido.Persistence.ContinuationStore`.
- Existing `Jido.Exec.Wait`, `Jido.Exec.Runtime`, and AgentServer durable-turn behavior.

### Outstanding Questions

None blocking. The first API can remain small because V3 is not released.

### Sources

- Direct product decisions in this conversation.
- [`../architecture/module-dependency-map.md`](../architecture/module-dependency-map.md)
- [`../architecture/package-vision.md`](../architecture/package-vision.md)
- [`../../lib/jido/exec.ex`](../../lib/jido/exec.ex)
- [`../../lib/jido/persistence/continuation_store.ex`](../../lib/jido/persistence/continuation_store.ex)
- [`../../lib/jido/agent_server/lifecycle.ex`](../../lib/jido/agent_server/lifecycle.ex)

## Planning Contract

### Product Contract Preservation

Product Contract unchanged.

### Current System

`Jido.Exec` compiles Actions and Flows to Runic. `Jido.Persistence.ContinuationStore` writes Runic event batches and detached facts through the common compare-and-swap Store contract. AgentServer Lifecycle currently owns Runner startup, manual checkpoint advancement, Signal wait receipts, timed wait resolution, and recovery. `Jido.Exec.Continuation` holds portable Agent turn receipts. The test-only `Jido.Test.Exec.WaitHost` also proves that waits can be represented in Runic facts without an Agent.

### Target System

```text
Jido.Signal
    -> Jido.Durable
       -> Jido.Durable.Runtime
          -> Jido.Exec + Runic.Runner
          -> Jido.Persistence.ContinuationStore
             -> Jido.Persistence.Store adapter

Jido.AgentServer
    -> Jido.Durable.Runtime
    -> Agent state commit, timers, cron delivery, and OTP lifecycle
```

`Jido.Durable` runs until it reaches a durable stop: completed, failed, uncertain, or waiting. Each Runic execution unit is checkpointed before later work starts. Wait input acceptance is saved separately from consumption. `signal/5` only confirms durable acceptance. `resume/3` performs later execution.

### Key Technical Decisions

#### KTD1: Use the existing Runic history as the recovery log

- **Decision:** Keep workflow events and facts in `Jido.Persistence.ContinuationStore`; add only small durable metadata required to restart a standalone execution.
- **Reason:** R3 requires reuse and a small concept count.
- **Rejected alternative:** Add a general journal behavior and record model.
- **Consequences:** Durable history is an implementation detail and can be compacted later. It is not a permanent audit API.
- **Governs:** R1, R3; U1, U2.

#### KTD2: Keep execution host-driven and process-independent

- **Decision:** A portable `Jido.Durable.Ref` identifies stored execution. Public start and resume operations can use a temporary Runner worker, but the durable identity is not a PID.
- **Reason:** R1 requires recovery outside AgentServer and after process loss.
- **Rejected alternative:** Make each durable execution a permanent GenServer.
- **Consequences:** Any process with the instance, reference, and storage access can resume execution.
- **Governs:** R1, R4; U1, U2.

#### KTD3: Persist Signals as inputs and receipts

- **Decision:** Initial Signal, resolved Flow instruction, portable runtime context, and definition fingerprint are saved as execution metadata. Wait delivery uses `Jido.Exec.Wait.input/2` and Signal ID deduplication.
- **Reason:** R2 defines Signal as the durable input and requires safe retries.
- **Rejected alternative:** Accept raw event maps or add a new durable input type.
- **Consequences:** Flow input is the Signal data map. Actions can read the full initial Signal from execution context.
- **Governs:** R2; U2, U4.

#### KTD4: Make scheduling a host capability

- **Decision:** Durable status exposes pending waits and `next_wake_at`. The host calls resume for timer deadlines and delivers cron occurrence Signals. Durable does not calculate cron expressions.
- **Reason:** R4 needs scheduled durability without a second scheduler.
- **Rejected alternative:** Add cron definitions, timers, and leases to Durable.
- **Consequences:** AgentServer can use its existing wait timers and Scheduler Plugin. Other hosts can use their own scheduler.
- **Governs:** R4, R5; U2, U3, U4.

#### KTD5: Move portable durable ownership out of Exec and live primitives out of AgentServer

- **Decision:** Move `Jido.Exec.Continuation` to `Jido.Durable.Continuation`. Put Runner checkpoint and wait-receipt mechanics in `Jido.Durable.Runtime`. AgentServer calls this runtime and keeps Agent commit policy.
- **Reason:** R1 and R5 require durability to exist independently while folding into AgentServer.
- **Rejected alternative:** Add a facade that leaves the real durable implementation inside AgentServer.
- **Consequences:** Existing callers and contract documents must move in the same unreleased V3 change.
- **Governs:** R1, R5; U1, U3.

### System Boundaries and Change Surface

| Surface | Current contract | Planned change | Compatibility or risk |
| --- | --- | --- | --- |
| `Jido.Exec` | Direct and managed Runic execution | Keep execution APIs; remove portable durable continuation ownership | V3 is unreleased; update all internal callers directly |
| `Jido.Durable` | Does not exist | Public start, resume, Signal acceptance, status, and result | New stable API needs small return shapes |
| Durable runtime | AgentServer Lifecycle functions | Shared internal runtime called by Durable and AgentServer | Must preserve checkpoint order and uncertainty rules |
| Continuation store | AgentServer-oriented registration and Runic history | General durable execution comments and use | Stored key shape stays compatible |
| AgentServer | Owns durable execution mechanics and Agent lifecycle | Delegate mechanics; retain Agent commit, timers, cron, and process policy | Existing durable-turn tests are the regression contract |
| Examples | Managed Runner examples and durable Agent examples | Add direct Durable examples | Must stay offline and deterministic |

### Implementation Units

#### U1: Establish Durable ownership

- **Outcome:** `Jido.Durable.Ref`, `Jido.Durable.Status`, `Jido.Durable.Continuation`, and internal runtime primitives exist under the Durable namespace.
- **Requirements:** R1, R3, R5.
- **Dependencies:** None.
- **Affected surfaces:** `lib/jido/durable*`, current Exec Continuation, AgentServer and Persistence references, contract documents, and continuation tests.
- **Implementation direction:** Move the continuation module without a compatibility wrapper. Extract checkpoint, resume, wait acceptance, and wait resolution code with unchanged ordering and error semantics.
- **Test scenarios:** Continuation validation and fingerprints remain exact; wait retries and conflicts remain exact; existing AgentServer durable-turn tests compile against the new owner.
- **Verification:** Focused Durable continuation and AgentServer durable-turn tests.
- **Completion signal:** No durable continuation or general wait-host policy remains owned by Exec or AgentServer.

#### U2: Add standalone Durable Flow API

- **Outcome:** Application code can start, resume, inspect, signal, and read a durable Flow without an Agent.
- **Requirements:** R1, R2, R3, R4.
- **Dependencies:** U1.
- **Affected surfaces:** Public Durable facade, durable metadata storage, ContinuationStore registration, Exec compilation and result projection, and new unit tests.
- **Implementation direction:** Require a running named Jido instance with a namespace and a configured or explicit persistence adapter. Derive a stable execution ID from the reference. Save metadata through existing fact storage. Run manual checkpoint units until a durable stop. Return public Status values. Keep Signal acceptance separate from resume.
- **Test scenarios:** Direct completion; stored result; wait and matching Signal; duplicate Signal; conflicting Signal ID; timer wake; definition fingerprint mismatch; missing persistence; nonportable context.
- **Verification:** `mix test test/jido/durable`.
- **Completion signal:** A direct Flow can survive worker suspension and resume from stored Runic state.

#### U3: Fold Durable into AgentServer

- **Outcome:** AgentServer uses `Jido.Durable.Runtime` for durable Flow work and keeps only Agent and host policy.
- **Requirements:** R5.
- **Dependencies:** U1.
- **Affected surfaces:** AgentServer Lifecycle, AgentServer public wait delivery, persistence record validation, durable-turn tests, and contract documents.
- **Implementation direction:** Replace extracted bodies with direct Durable Runtime calls. Keep Agent acceptance/commit records, wait timer arming, Scheduler Plugin use, and OTP recovery in AgentServer.
- **Test scenarios:** Durable Agent completion, process recovery, wait resume, timer wait, cancellation, and checkpoint cleanup remain unchanged.
- **Verification:** `mix test test/jido/agent_server/durable test/jido/agent_server/durable_turn`.
- **Completion signal:** AgentServer durable behavior passes with shared runtime ownership.

#### U4: Add examples and documentation

- **Outcome:** Supported offline examples show direct completion, Signal wait resume, and host-driven scheduled resume.
- **Requirements:** R2, R4, R6.
- **Dependencies:** U2, U3.
- **Affected surfaces:** `examples/05_flow_durability`, paired example tests, examples index, component/docs index if needed.
- **Implementation direction:** Add small examples that use the public Durable API. Use ETS or temporary File persistence and deterministic clocks. State that cron calculation and delivery belong to the host.
- **Test scenarios:** Every example runs through its paired test and produces the documented result.
- **Verification:** `mix test.examples test/examples/05_flow_durability`.
- **Completion signal:** Examples pass and explain the host boundary without introducing a scheduler.

### Work Graph

- Initial frontier: U1.
- After U1: U2 and U3 can proceed from the shared runtime contract.
- Final integration: U4 after the public API and AgentServer integration agree.
- Critical path: U1 -> U2 -> U4.

### Verification Contract

| Gate | Applies to | Evidence | Done signal |
| --- | --- | --- | --- |
| Durable unit behavior | U1-U2 | Focused Durable tests | Start, wait, Signal retry, resume, status, and result pass |
| AgentServer integration | U1, U3 | Existing durable and durable-turn tests | No durable Agent regression |
| Examples | U4 | Supported example suite | New examples pass offline |
| Persistence and Exec regression | U1-U3 | Focused Exec and Persistence tests | Store and execution contracts pass |
| Repository | All | Format, warning-free compile, standard test suite | No relevant regression |

Working directory: repository root.

```sh
mix test test/jido/durable
mix test test/jido/agent_server/durable test/jido/agent_server/durable_turn
mix test test/jido/exec test/jido/persistence
mix test.examples test/examples/05_flow_durability
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

Requirement traceability:

| Requirement | Units | Verification |
| --- | --- | --- |
| R1 | U1, U2, U3 | Direct Durable tests and AgentServer integration |
| R2 | U2, U4 | Signal wait, duplicate, and conflict tests |
| R3 | U1, U2 | Source review and Persistence/Exec regression tests |
| R4 | U2, U3, U4 | Wait status, timer wake, and scheduled Signal example |
| R5 | U1, U3 | Existing durable AgentServer suites |
| R6 | U4 | Example suite and unit test paths |

### Rollout and Recovery

This is an unreleased V3 API change. No production migration is in scope. Existing Runic execution keys and Store adapter behavior remain unchanged. A failed implementation can be reverted to checkpoint commit `1672fb43` without changing external storage adapters.

### Risks and Assumptions

- **Risk:** A refactor can change manual checkpoint ordering. Existing process-loss and wait checkpoint tests detect this.
- **Risk:** Public status can report live state that is not yet durable. Status must derive from the committed workflow when no live checkpoint has completed.
- **Risk:** Signal acceptance and workflow consumption can separate during a crash. Acceptance must commit first, and resume must consume the saved receipt.
- **Risk:** Definition code can change between start and resume. Saved metadata must check the current fingerprint before new work starts.
- **Assumption:** A named Jido instance supplies the Runner and runtime registry. This does not couple Durable to an Agent or AgentServer.
- **Assumption:** The host owns cron calculation and delivery. Durable only accepts the resulting Signal or wake call.

### Open Planning Decisions

None.

### Definition of Done

- `Jido.Durable` runs and resumes a persisted Flow without Agent types.
- Durable external input is `Jido.Signal`.
- Waits persist, duplicate Signal delivery is inert, and `next_wake_at` is public.
- AgentServer uses the shared durable runtime and its current durable suites pass.
- No public Journal, scheduler, queue, new dependency, or new package exists.
- Basic unit tests and supported offline examples pass.
- Format, compile, and standard tests pass.
- The final local implementation commit is created. No push occurs.

### Planning Sources

- Current repository code and tests listed in Product Contract Sources.
- Checkpoint commit `1672fb43`.

## Adapter Results

- Markdown: canonical at `docs/plans/2026-11-10-1258-durable-flow-execution-plan.md`
- HTML: not requested
- Beadwork: not requested
