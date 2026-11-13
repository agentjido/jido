---
title: Refine the immutable Jido Agent boundary
type: implementation-plan
date: 2026-11-11
last_reviewed: 2026-11-11
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Refine the immutable Jido Agent boundary

## Goal Capsule

- Objective: Make `Jido.Agent` the small, process-free data and decision layer for one immutable Agent definition and its changing state.
- Means: Remove Turn and definition-patch concepts, centralize Action-to-Flow lowering, and replace complete definitions through one explicit AgentServer administration path.
- Authority: Change local files in the `jido` repository and verify the complete change. Do not commit or push.
- Stop conditions: Stop if the work needs a new workflow language, an in-flight durable Flow migration, a compatibility layer, or a change in another package.
- Next executor: Jido implementation worker.

## Product Contract

### Summary

`Jido.Agent` owns immutable definitions, instances, route selection, Plugin preparation and reduction, state transition, and runtime Directives. A command prepares one bound Flow instruction and returns a candidate Agent with changed state. It cannot change routes, Plugins, topology members, or connections. AgentServer owns OTP lifecycle and can replace an idle activation with one complete trusted definition.

### Problem Frame

The current Agent layer exposes a Turn value, authored managed or durable policy, Diff, ordered mutation patches, and many mutation Directives. This lets domain work rewrite its own definition during a Turn. AgentServer then needs a second commit path that pauses Plugins and reconciles topology after ordinary state work. The same code also lowers Actions to Flows more than once.

### Requirements

- **R1:** `Jido.Agent` must remain process-free and independent of AgentServer, Durable, persistence, and execution lifecycle policy.
- **R2:** An Agent definition is immutable for one activation. A command can change complete Agent state and return runtime effects only.
- **R3:** Remove `Jido.Agent.mutate/2`, public `Jido.Agent.Diff`, `Jido.Agent.Mutation`, and all definition-mutation Directive modules and constructors.
- **R4:** Keep topology authoring and validation static. Runtime child start and stop remain explicit AgentServer effects and do not edit the Agent definition.
- **R5:** Every selected Action or Flow becomes one bound Flow instruction through `Jido.Exec.Runtime.flow_instruction/1`.
- **R6:** Remove `Jido.Agent.Turn`; the private Runner prepared value holds the selected route, source Signal, and one bound Flow instruction.
- **R7:** AgentServer selects managed or durable execution from persistence capability, not authored handler kind.
- **R8:** A permanent definition change accepts one complete Agent Codec document with an explicit trusted Catalog.
- **R9:** AgentServer definition upgrade requires an idle supervised activation, validates the new definition, optionally migrates state through one Action, validates and persists the candidate with revision control, publishes the local checkpoint, and restarts the AgentServer under the same stable Agent Address.
- **R10:** A running or waiting durable Flow is active. Definition upgrade must return `:agent_busy`; it must not migrate that Flow.
- **R11:** Move compiler-only option and input-Signal helpers off the `Jido.Agent` facade. Move raw state transition validation to `Jido.Agent.Validation`.
- **R12:** Examples and tests must show pure Agent state work, one-step Action lowering, explicit runtime children, complete definition upgrade, stable Address and changed PID, and busy-upgrade rejection.

### Acceptance Examples

- An Action route prepared by Runner contains `%Jido.Instruction{kind: :flow}` and no execution mode.
- Direct `Jido.Agent.cmd/3` and AgentServer without persistence produce the same state and Directives.
- AgentServer with persistence runs an Action route through the durable Flow path.
- A complete Agent document decodes through `Jido.Codec` with an explicit `Jido.Catalog`, upgrades an idle activation, retains its stable Agent Address, and runs in a new AgentServer PID.
- An upgrade request during a running or waiting Flow returns `{:error, :agent_busy}` and changes no state or definition.

### Success Criteria

- No Turn, execution mode, Agent mutation, Agent Diff, or definition-mutation Directive code remains.
- Ordinary Turn commit has one state path and no Plugin or topology reconfiguration branch.
- AgentServer definition upgrade is the only live definition-change path and uses OTP restart.
- Focused Agent, AgentServer, Durable, Persistence, contract, and example tests pass.
- Format, warning-free compile, and the standard test suite pass.

### Scope Boundaries

In scope:

- `Jido.Agent`, Runner, Directive, static Topology, tests, contracts, guides, and examples.
- The AgentServer work needed for prepared Flow instructions, simple state commits, explicit runtime children, and whole-definition upgrade.

Out of scope:

- Migration of an active or waiting durable Flow.
- Definition patch APIs, hot route changes, hot Plugin reconfiguration, and hot topology reconciliation after a Turn.
- AgentServer public API redesign beyond the definition-upgrade operation.
- Changes in `jido_action`, `jido_signal`, or `jido_ai` packages.

### Key Decisions

- Agent state is mutable; the definition is not.
- Runtime child effects are operational and are not topology edits.
- `Jido.Instruction` is the only prepared execution value.
- Persistence capability selects durable execution.
- Definition upgrade accepts a complete Codec document and explicit Catalog, never a patch.
- Upgrade restarts the AgentServer. Its PID can change. `Jido.Agent.Address` stays stable.
- The first version rejects upgrade while any Turn or durable wait is active.

### Rejected Alternatives

- Keep mutation Directives as internal values: they retain the second commit and reconciliation path.
- Hot-swap the definition in the current PID: this requires quiescence rollback for Plugins and topology and makes partial replacement possible.
- Migrate an active durable Flow: saved workflow identity and code compatibility need a separate product contract.
- Accept an Agent struct directly for upgrade: the Codec and Catalog boundary is the trusted complete-definition input path.

### Dependencies

- Existing Agent Codec, Catalog, Validation, Address, Persistence compare-and-swap, activation checkpoint, and OTP supervisor behavior.
- Existing Exec Action-to-Flow lowering and Durable runtime.

### Outstanding Questions

None blocking. V3 is unreleased, so removed mutation and Turn surfaces get no compatibility layer.

### Sources

- Direct product decisions in this conversation.
- [`../../lib/jido/agent.ex`](../../lib/jido/agent.ex)
- [`../../lib/jido/agent/runner.ex`](../../lib/jido/agent/runner.ex)
- [`../../lib/jido/agent/directive.ex`](../../lib/jido/agent/directive.ex)
- [`../../lib/jido/agent_server.ex`](../../lib/jido/agent_server.ex)
- [`../../lib/jido/agent_server/supervisor.ex`](../../lib/jido/agent_server/supervisor.ex)

## Planning Contract

### Product Contract Preservation

Product Contract updated by the direct refocus request: Agent definitions are immutable per activation, and full AgentServer definition replacement supersedes mutation patches.

### Current System

Runner builds a public Turn and records authored lifecycle policy. A successful Turn can carry definition mutation Directives. Runner applies them to the Agent value, and AgentServer computes a Diff, pauses changed Plugins, saves the candidate, reconciles topology and Plugin processes, and resumes work.

### Target System

```text
Signal + Agent instance
    -> route and Plugin preparation
    -> one bound Flow Instruction
    -> Exec or AgentServer host execution
    -> complete next state + runtime effects
    -> validate, persist, commit, dispatch

Complete Agent Codec document + trusted Catalog
    -> validate new definition
    -> require idle supervised activation
    -> migrate and validate state
    -> compare-and-swap persistence and local checkpoint
    -> restart AgentServer under the same Agent Address
```

### Key Technical Decisions

#### KTD1: Replace Turn with one bound Flow instruction

- Decision: `Jido.Agent.Runner.Prepared` stores one `%Jido.Instruction{kind: :flow}`.
- Reason: Instruction already carries target, input, and context.
- Consequence: Direct, managed, durable, and handoff paths consume the same value.
- Governs: R1, R5-R7.

#### KTD2: Delete definition patches

- Decision: Remove mutation modules, mutation Directives, Diff, and ordinary commit reconciliation.
- Reason: One activation has one immutable definition.
- Consequence: Turns have one state commit path. Static topology and Plugin declarations change only through full upgrade.
- Governs: R2-R4.

#### KTD3: Use whole-definition replacement and OTP restart

- Decision: `Jido.AgentServer.upgrade/3` accepts a complete Agent Codec document plus `catalog:`, optional `migrate:`, context, and timeout. It rejects non-idle work. After a successful revision-controlled save, it publishes the candidate checkpoint and exits so its supervisor starts a new worker.
- Reason: This creates one atomic administration boundary and lets OTP rebuild all runtime resources.
- Consequence: Callers resolve the stable Address again after upgrade. PID identity is not stable.
- Governs: R8-R10.

#### KTD4: Keep runtime children operational

- Decision: Keep AgentServer child start and stop effects. They do not change the authored topology.
- Reason: Temporary work has a runtime lifetime, not a definition lifetime.
- Consequence: Recovery does not infer temporary children from Agent data.
- Governs: R4.

#### KTD5: Keep the Agent facade at the domain boundary

- Decision: Compiler helpers move to DSL, and raw state transition validation moves to Validation.
- Reason: They are implementation support, not stable Agent domain operations.
- Governs: R1, R11.

### Implementation Units

#### U1: Collapse Agent execution preparation

- Outcome: Remove Turn and lifecycle policy. Prepare one bound Flow instruction and let AgentServer choose runtime from persistence.
- Requirements: R1, R5-R7.
- Verification: Agent evaluation, selection, flow, handoff, and durable Action tests.

#### U2: Remove self-modifying definitions

- Outcome: Delete mutate, Diff, Mutation, mutation Directives, state-bound topology reconfiguration, and the ordinary commit reconciliation path.
- Requirements: R2-R4.
- Verification: Agent API, Directive, static topology, AgentServer state commit, runtime child, and Plugin tests.

#### U3: Add whole-definition AgentServer upgrade

- Outcome: Complete trusted definition input, optional state migration, idle gate, revision-controlled save, local checkpoint, OTP restart, stable Address, and busy rejection.
- Requirements: R8-R10.
- Verification: Local and persistent upgrade tests, stable Address tests, PID replacement, invalid document, migration failure, persistence failure, and active Flow rejection.

#### U4: Align facade, examples, guides, and contracts

- Outcome: No removed surface is taught or listed. Examples show static authoring, runtime child effects, and complete definition upgrade.
- Requirements: R11-R12.
- Verification: API contracts, documentation checks, and co-located example tests.

### Work Graph

- Initial frontier: U1 and U2.
- Integration: U3 after the simple commit path is stable.
- Final alignment: U4.
- Critical path: U1 -> U2 -> U3 -> U4.

### Verification Contract

| Gate | Applies to | Done signal |
| --- | --- | --- |
| Agent boundary | U1-U2 | Agent, Directive, static Topology, and API tests pass |
| Host execution | U1-U3 | Managed, durable, wait, handoff, persistence, and upgrade tests pass |
| Examples | U4 | Agent basics, runtime, topology, and durable Agent examples pass |
| Package regression | All | Format, warning-free compile, and standard test suite pass |

Working directory: repository root.

```sh
mix test test/jido/agent test/jido/agent_test.exs
mix test test/jido/agent_server test/jido/durable test/jido/persistence
mix test.examples examples/01_agent_basics examples/08_runtime examples/10_topologies examples/14_durable_agents
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

### Rollout and Recovery

This is an unreleased V3 breaking cleanup. Stored Agent documents remain complete documents. No patch decoder or Turn compatibility module is added. A failed implementation can be reverted as one local change set.

### Risks and Assumptions

- Risk: Removing reconciliation can expose a hidden mutation producer. Repository-wide searches and the full suite must find it.
- Risk: Upgrade can save successfully but fail to restart. The stable Address will report recovery or not found; persistence keeps the accepted revision for a later restore.
- Risk: A caller can hold the old PID after upgrade. Documentation and examples must use the stable Address for later operations.
- Assumption: Runtime child effects already provide the required temporary-child capability.
- Assumption: A new definition can accept old state directly or use one explicit migration Action.

### Definition of Done

- Turn, execution mode, mutate, Mutation, Diff, and mutation Directives are gone.
- Ordinary work has one state commit path.
- Agent prepares one bound Flow instruction.
- AgentServer uses persistence capability for durable execution.
- Complete definition upgrade validates, persists, restarts, and retains stable Address.
- Active or waiting Flow upgrade is rejected.
- Examples, focused tests, format, compile, and full tests pass.

### Planning Sources

- Current repository source, tests, contracts, guides, and examples.
- Direct product decisions in this conversation.

## Adapter Results

- Markdown: canonical at `docs/plans/2026-11-11-1815-agent-boundary-refactor-plan.md`
- HTML: not requested
- Beadwork: not requested
