---
title: Shared blackboard for Jido agent topologies
type: implementation-plan
date: 2026-11-23
last_reviewed: 2026-11-23
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Shared blackboard for Jido agent topologies

This plan describes the initial in-memory board. The follow-up adds
[instance persistence and board retirement](../adr/0021-shared-blackboard-ownership.md)
and extends the inventory example to 20 and 100 counters.

## Start with an example

A warehouse desk owns an `inventory` board. One counter agent posts a count
of 12 for bin A. A second counter agent reads the board and sees 12. This is
the first runnable slice in Jido core.

Extend the same example in this order:

1. Both counters read the same revision. They submit different counts for
   bin A. One patch succeeds. The other gets a conflict. A fresh read shows
   the successful count.
2. Restart the board and show that a patch with a revision from the previous
   board fails.
3. Use the Client Plugin for both counters. Restart one counter while the
   board stays live and show that the counter reads the current count.
4. Add a Statechart that waits for the result of its own patch request. A
   matching success advances the chart. A conflict or an uncertain result
   sends it back to read the board.

Start implementation with the example's README and a behavior test for the
first slice. Write the setup, the calls an agent author makes, and the
expected result. Use those calls to shape the public Plugin options, snapshot,
and patch API. Add each scenario to the same example as its behavior becomes
available. Use the core [Statechart Plugin example](../../examples/11_built_in_capabilities/11_08_statechart_plugin/README.md)
as a reference for the chart step.

## Goal Capsule

- **Objective.** Let agents in a topology read and update one shared board, with a clear result when updates race.
- **Means.** Start with a runnable core example. Add the board owner and client Plugins in the slices the example needs. Use existing Plugin lifecycle and effect callbacks.
- **Authority.** This request authorizes the plan. A later implementation request can authorize local code, tests, and documentation in Jido core.
- **Stop condition.** Finish local verification of the core feature and example.
- **Next executor.** Jido core maintainer or implementation agent.

## Product Contract

### Summary

An agent topology can use a named board to share current facts such as a work result, an evaluation, or a decision.

### Problem Frame

Topology members have separate Agent state. Signals can carry updates, but a member that starts later needs a way to read the latest values. Two members can also make decisions from the same view of the data.

### Actors

The root agent owns the board. Member agents read and publish values. The topology author chooses which agents use the board and which Signals require its data.

### Requirements

- **R1.** A root agent can start a local board. Members can resolve that board by configuration and read its current snapshot.
- **R2.** Members can submit a conditional patch. The board applies the complete patch if the expected revision matches, or reports a conflict without changing the data.
- **R3.** A client can read a snapshot as turn input and request a patch after the turn commits. It can distinguish a successful patch, a conflict, and an unavailable or uncertain result.
- **R4.** A restarted client can read the board again. A new board starts from its configured initial values and rejects revisions from a previous board process.
- **R5.** A runnable example in Jido core shows two members sharing the board. It shows how a Statechart can act on a result Signal.

### Key Flows

A member receives a Signal and reads a board snapshot during admission. Its handler returns a patch Directive with the revision it read. After the agent commits, the client sends the patch to the board. The board answers, and a result Signal starts a new turn in the member.

### Acceptance Examples

- Two members read the same revision and submit different patches. One succeeds, one reports a conflict, and a later read shows the winner's data.
- Restart a member while the board remains live. The member reads the current data. Restart the board and try a write with its old revision. The board rejects that revision.
- A Statechart that waits for confirmation advances on a matching success Signal. Conflict or an uncertain result leads to a read before a new decision.

### Success Criteria

The core example and contract tests prove the requirements through the public Plugin and client entry points.

### Scope Boundaries

The first version serves trusted agents on one BEAM node. A board lives with its owner resource and stores data in memory. Durable storage, cross-node access, subscriptions, task claims and leases, external access grants, and tool integrations are outside this plan. All implementation and proof belong in the Jido core repository.

### Key Decisions

Use explicit board configuration and an opt-in Plugin pair.

### Rejected Alternatives

A public ETS table gives each writer direct access. A board owner gives all writers the same validation and revision check.

### Dependencies

Use the Jido core AgentServer, Plugin lifecycle, Signals, Directives, and OTP. This proposal adds a core capability without a dependency change or a cross-package release sequence.

### Outstanding Questions

None that prevent this local, in-memory version. See Open Planning Decisions for future scope.

### Sources

The request and the preceding investigation supply the scope. The core [Topology guide](../../guides/composition/declare-agent-topology.livemd) describes member state and startup.

## Planning Contract

### Product Contract Preservation

The plan preserves the request for a shared blackboard and a server/client Plugin design within Jido core. The example belongs in core.

### Current System

The [Behavior Tree blackboard](../../lib/jido/behavior_tree/blackboard.ex) is a map value shared during tree execution. The [Statechart Plugin](../../lib/jido/plugin/statechart.ex) commits a session per agent. Statechart [assignments](../../lib/jido/statechart/turn.ex) update that session's data. The [Bus Manager](../../lib/jido/plugin/bus/manager.ex) and [Bus Client](../../lib/jido/plugin/bus/client.ex) show how agents own and connect to a named resource. The [worker bootstrap](../../lib/jido/agent_server/worker.ex) starts root Plugin resources before it reconciles topology members.

### Target System

The proposed modules are `Jido.Blackboard`, `Jido.Plugin.Blackboard.Server`, and `Jido.Plugin.Blackboard.Client`. The Server Plugin starts one board process. The public client resolves the board by instance and name on each call. The Client Plugin supplies snapshots on configured Signals and sends validated patch requests after commit. The board serializes writes.

### Key Technical Decisions

- **KTD1. One local owner.** Use a supervised GenServer with a map. Follow the Bus naming pattern and use a separate Registry key space for blackboards under the existing application supervision tree. A registration identifies the Jido instance and board name. Duplicate registration fails startup. The root can start its board before its members start. A named endpoint avoids keeping a stale PID in a definition. Governs R1 and R4, U1 and U2.
- **KTD2. Conditional writes.** Treat the revision as an opaque, portable token that identifies both the board process generation and the snapshot version. Start a new generation whenever the board process starts. Use a patch of string keys and portable values with optional key removal. Reject a patch that both sets and removes the same key. Validate and compare the revision before changing the map. Each accepted patch advances the revision once. Each rejected patch leaves it unchanged. The owner performs the check and write together. Governs R2 and R4, U1 and U3.
- **KTD3. Reads at admission, writes after commit.** Read only on configured Signal paths. Return the snapshot as transient client input. A selected read that fails returns an admission error. Pure evaluation can use an explicit snapshot in its input Signal. Return a validated patch Directive from the handler and dispatch it after commit. Use the caller's request ID to correlate an asynchronous result Signal. A successful agent commit and a successful board write are two distinct events. Governs R3 and R5, U2 and U3.
- **KTD4. Signals connect the board to charts.** Route the outcome through the existing Statechart event path in the example. Use an explicit snapshot or copied values as chart data. A direct live read from a transition would tie evaluation to an external process and allow the values to change between reads. Governs R5 and U3.

### System Boundaries and Change Surface

| Surface | Planned contract | Compatibility or risk |
| --- | --- | --- |
| Board identity | Required local Jido instance and explicit binary board name. Use the same name on the root and its members. | Additive configuration. Test duplicate names and instance isolation. Board names identify resources and do not grant access. |
| Snapshot and patch | `read` returns values and revision. `patch` accepts the expected revision plus the changes. It returns the new snapshot or an error with a stable conflict, validation, unavailable, or timeout reason. | A timeout after sending a patch can have an unknown outcome. Re-read before taking action. A retry with the old revision cannot apply a second write in the same generation. |
| Agent effects | Use a custom patch Directive and a result Signal with board identity, request ID, outcome, and revision when available. Send the result back to the originating agent asynchronously. Bound board requests within the effect budget. | A failed turn does not dispatch. A committed turn can lose its result Signal during restart or cancellation. A result timeout calls for reconciliation, and the Plugin does not automatically retry a patch. |
| Lifecycle | The Server Plugin registers on startup. The client resolves the resource on each operation. Stop and restart follow activation supervision. | Board contents live for one board process generation. Same-name recreation makes old revisions invalid. |
| Core architecture | Give the capability its own Reach and Covenant ownership. Add the guide, example, and any required architecture and ADR entries during implementation. | Existing chart and behavior-tree execution paths continue through their current APIs. Existing Agent definitions need no migration. |

### Implementation Units

#### U1. Serve a local board with conditional updates

- **Dependencies.** None. Covers R1, R2, R4 and KTD1–KTD2.
- **Surfaces.** First slice of the supported core example, new board API and owner Plugin, Registry supervision in [Jido.Application](../../lib/jido/application.ex), focused tests, Reach and Covenant ownership.
- **Direction.** Start with the inventory example's setup and behavior test. Use the board API directly in the first slice and get that slice passing. Then add the checks for concurrent writes and board restart. Validate initial values and patch values at the API boundary. Keep the revision check and patch in one server call. Use synchronous reads and writes with bounded timeouts. Keep board data out of Agent checkpoints.
- **Proof.** Use public calls from concurrent processes. Verify one winner, conflict without partial writes, invalid data, unavailable board, duplicate name, instance isolation, and rejection of an old revision after recreation.
- **Completion.** The first example slice passes through the public API. A supervised root starts and stops the board, and the focused tests pass.

#### U2. Connect member agents

- **Dependencies.** U1 supplies a named board API. Covers R1, R3, R4 and KTD1–KTD3.
- **Surfaces.** Client Plugin, patch Directive, result Signal, AgentServer integration tests.
- **Direction.** Update the inventory example to drive both members through the Client Plugin. Use `admit/3` for selected reads and `dispatch/4` for patches. Validate static options at startup. Resolve the live board when a selected read or write needs it. Keep startup free of a synchronous call to the root AgentServer.
- **Proof.** Start a real topology. Verify selective admission, pure evaluation without live I/O, no write after a failed turn, result correlation, conflict, unavailable board, timeout with an unknown outcome, and read after member restart. Verify that the member can reconcile from a read when it misses a result.
- **Completion.** A member can read, request a patch, and observe the outcome through its routes. The focused tests pass.

#### U3. Prove the topology workflow in core

- **Dependencies.** U2 supplies live client behavior. Covers R2–R5 and KTD2–KTD4.
- **Surfaces.** Supported core topology example, built-in Plugin guide, Statechart and Behavior Tree regression tests, architecture map and ADR index.
- **Direction.** Complete the inventory example with the Statechart that reacts to its patch result. Use the example as the first walkthrough in the Plugin guide. Describe board scope, restart behavior, and reconciliation after a timeout.
- **Proof.** Run the example offline. Verify one winning update, one conflict, and a correct read after restart. Check that the chart advances only for the matching confirmation. Run the existing chart and tree tests.
- **Completion.** The supported example and all final verification gates pass.

### Work Graph

U1 starts with the example and its first behavior test. U1 → U2 → U3 is the
integration order. Extend and run the same example at each step.

### Verification Contract

| Requirements | Gates | Expected evidence |
| --- | --- | --- |
| R1, R2 | First example slice in U1 | One member posts a count and a second member reads it through the public board API. |
| R1, R2, R4 | Focused board and owner tests, then the load suite with a concurrent writer case | A valid board starts and stops. A race has one winner. A stale revision cannot update a recreated board. |
| R1, R3, R4 | Focused member tests through AgentServer | Turn input is selective. Writes follow commit. A client reports and handles conflict, unavailability, and uncertainty. |
| R2–R5 | Offline example and existing chart and tree tests | Observable topology behavior and existing execution behavior pass. |
| R1–R5 | Architecture, contracts, authoring, formatting, and offline CI | The capability conforms to core boundaries and existing callers pass. |

From the Jido core repository, use its configured Mix environment. Run each unit’s new test files with `mix test`. Then run the core checks.

```sh
mix test test/jido/plugin/statechart/statechart_test.exs test/jido/plugin/behavior_tree_test.exs
mix test.examples
mix test.load
mix test.authoring
mix test.contracts
mix reach.check --arch --smells
mix format --check-formatted
mix quality
mix test.ci
```

### Rollout and Recovery

Enable the Plugins on the example topology first. Existing topologies opt in through their definitions. Disabling the Plugins and their routes removes access to the board. Stopping the board drops its in-memory values. Recreate it from the configured initial values, and require clients to read a current revision before another write.

### Risks and Assumptions

- The client can time out after the board has applied a write. Treat that result as unknown. The next read is authoritative for the current contents. It may be insufficient to determine who applied a particular change.
- The board may restart while clients hold snapshots. A generation-specific revision prevents an old snapshot from matching a new board.
- Each board keeps a small map of shared facts. Whole snapshots copy data to readers. The initial design assumes a small, trusted topology.
- Planning evidence comes from the local core checkout at `b9dd510a` with concurrent work in the tree. Verify the current core integration base before implementation.

### Open Planning Decisions

None for U1–U3. The core maintainer can make separate product decisions on durable boards, subscriptions, or task claims if a later request brings them into scope.

### Definition of Done

U1–U3 pass their completion checks. Each requirement has passing evidence through its normal core entry point. The guide states the failure and restart behavior. Core verification passes. All feature changes belong to the Jido core repository.

### Planning Sources

[Core instructions](../../AGENTS.md) · [Plugin resources](../../guides/plugins/plugin-supervised-resources.livemd) · [Plugin input](../../guides/plugins/plugin-input-and-routes.md) · [Custom Directives](../../guides/plugins/plugin-custom-directives.livemd) · [Turn and effect ordering](../../guides/core-concepts/signal-to-effects.md) · [Mix commands](../../mix.exs)

## Adapter Results

- Markdown. Canonical in this file.
- HTML. Outside this request.
- Beadwork. Outside this request.
