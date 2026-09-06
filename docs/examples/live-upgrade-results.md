# Live Agent and topology upgrades

Date: 2026-09-05. Core baseline: `a23091b4` on `v3-spike`.

Three new examples have **12 enabled tests: nine pass and three fail**.
The failures identify three proposed core contracts. All ten upgrade ideas
are recorded below. The other seven ideas still need executable tests.

This pass adds examples and tests. It does not add a core upgrade API.
The checks use current public APIs and one isolated Action code load.
They do not change private AgentServer or Controller state.
The fixed Agent definitions use agent and routes DSL blocks. Wallets declare
their audit Plugin in the agent block. The Action reload remains an explicit
part of the Turn revision test.

The [DSL validation run](dsl-acceptance-output.txt) confirms that the authoring
change preserves the combined result: 34/45 passing checks, with the same
11 acceptance failures. The acceptance assertions are unchanged.

## Results

| Example | Pass | Fail | What it proves |
| --- | ---: | ---: | --- |
| [Turn upgrade](../../examples/99_research/99_14_turn_upgrade/README.md) | 2 | 1 | An idle Agent can use new Action code on the same PID. A code load between Flow steps mixes revisions in one Turn. |
| [State migration](../../examples/99_research/99_15_state_migration/README.md) | 3 | 1 | A static schema that accepts both formats permits atomic domain and Plugin migration. An old schema cannot accept an unplanned new format. |
| [Topology upgrade](../../examples/99_research/99_16_topology_upgrade/README.md) | 4 | 1 | Pure Agent plan comparison and full replacement work. Live target submission has no update path. |

Run only these examples:

```sh
mix test test/examples/99_research/99_14_turn_upgrade test/examples/99_research/99_15_state_migration test/examples/99_research/99_16_topology_upgrade --include example --seed 0 --trace
```

The command returns exit status 2 until the three acceptance targets pass.
The [saved output](live-upgrade-output.txt) contains every test and failure.
No test is skipped. Each failed assertion states the desired behavior.

These are limits of the available operations, not regressions against their
current contracts. When core gains explicit upgrade operations, connect these
tests to those operations. Do not weaken schema validation, change duplicate
startup semantics, or assume that arbitrary code loads are safe upgrades.

## Core contracts to add

### UP-01: One definition revision for each Turn

The example runs a Flow with two calls to the same Action module. Revision 1
adds one. Revision 2 adds ten. A barrier pauses the Flow after the first call.
The test loads revision 2, then releases the second call.

**Observed:** The active Turn returns total 11 and revisions `[1, 2]`.
The next Turn returns total 20 and revisions `[2, 2]`. Both commit on the same
Agent PID. Without a deployment, the total is 2 and revisions are `[1, 1]`.

**Required:** Retain revision 1 for the complete active Turn. Switch to
revision 2 at an explicit boundary. Include Flow steps, routes, schemas, and
Plugin code in the definition policy. Check executed behavior, not just a
revision label.

**Limit:** This probe loads one isolated Action module. It does not execute an
OTP release upgrade. A core upgrade design must control code activation or
use separate versioned modules. A revision field alone cannot prevent this
failure. The loader uses no forced code purge and restores compiler options.

### UP-02: Install a new definition with migrated state

The wallet changes from `%{format: 1, balance: 100}` to
`%{format: 2, amount: 100, currency: "USD"}`. Its Plugin changes an event list
to an entry list and saves the upgrade ID. A normal Turn commits both changes.

**Observed:** This works on the same PID when the static schema already
accepts both formats. Invalid currency preserves the complete old snapshot.
A saved migration survives process replacement. Repeating its upgrade ID
does not apply the transformation again. A different ID is rejected.

The same Action fails on the strict old wallet. Core correctly rejects the
new format and the missing old balance field.

**Required:** Add an explicit operation that validates the source revision,
builds a candidate with the target definition, migrates complete domain and
Plugin state, and commits the matching definition and state together.
Failure must leave the old definition and state usable.

**Limit:** Application state migration within a predeclared schema already
works. It is not a definition upgrade. The example has no live Plugin runtime,
external side effect, concurrent upgrade request, or crash during the commit.
An upgrade ID prevents repeated transformation; a repeated ordinary Turn can
still advance the state version. Ordinary restore must remain separate from
an explicit migration request.

### UP-07: Apply a new topology target without replacing unchanged members

The example builds plans for three and five workers, plus one observer Agent.
A pure comparison reports added, removed, changed, and unchanged Agent keys.
A second worker definition performs ten times the work. Its behavior is
tested on real Agents. Invalid target validation leaves live workers unchanged.

**Observed:** A full controller replacement can grow three workers to five
and restore saved worker state. It stops all old workers and the unchanged
observer. Each receives a new PID. Submission of the target through current
Controller startup returns `already_started`.

**Required:** Add a live target update operation. Validate the whole target
before effects. Apply additions, removals, and definition changes under an
explicit policy. Retain unchanged Agent IDs, PIDs, and committed state.
Repair must use the accepted target, rather than recreate removed members.

**Limit:** The example comparison covers local Agent plan entries only.
It is not a complete topology diff or rollout controller. It does not compare
Bus resources, ownership, subscriptions, or embedded code revision changes
under the same module name. Persistence uses the local ETS adapter. Worker
module changes also need an explicit storage and state migration policy.

## All ten upgrade cases

Choose upgrade mode explicitly. A same-process upgrade retains ID and PID.
A replacement upgrade retains logical ID and supplies a new PID. Both need
an admission policy and a state migration boundary.

| ID | Concrete feature | Example and acceptance target | Current coverage |
| --- | --- | --- | --- |
| UP-01 | Turn revision boundary | Pause a two-step Flow, request revision 2, then resume. Both old steps add one; the next Turn has two steps that each add ten. | Turn example: gap reproduced. |
| UP-02 | Definition and complete-state migration | Convert wallet and owned audit state together. Invalid target or migration failure retains the old complete state and definition. | State example: compatible migration passes; schema change fails. |
| UP-03 | Admission during upgrade | Submit old and new command formats before, during, and after migration. Apply an explicit queue, adapter, or rejection policy. Bound the queue and account for every accepted command. | Not yet tested. |
| UP-04 | Pending work continuity | Upgrade an Agent awaiting approval, a child result, and a scheduled occurrence. Preserve work IDs. Accept, retry, adapt, or cancel each old result by a declared policy. | Not yet tested. |
| UP-05 | Plugin runtime replacement | Replace a feed runtime after state migration. Wait for readiness before activation. Reject old input generations. Readiness failure keeps the old runtime usable; success closes old resources. | Not yet tested. |
| UP-06 | Durable upgrade and recovery | Stop the Agent before, during, and after the upgrade write. Restore one complete old or new definition/state pair. Reload uncertain writes. Do not apply migration twice. | Not yet tested; saved compatible-state migration is only a control. |
| UP-07 | Topology target planning and application | Grow three workers to five, remove two, or revise one component. Reject invalid plans without effects. Keep unchanged members and make repair follow the new target. | Topology example: Agent diff and full replacement pass; live growth fails. |
| UP-08 | Rolling topology upgrade | Upgrade ten workers in batches of two. Keep at least eight available. Check actual revision and readiness. Stop later batches when readiness fails. Test the mixed-version message protocol. | Not yet tested. |
| UP-09 | Connection and ownership migration | Move workers to a new coordinator and replace result subscriptions. Retain one accepted result owner. Close old subscriptions. Stopping the old parent must not stop transferred workers. | Not yet tested. |
| UP-10 | Resumable topology upgrade | Stop the controller after two of five migrations. Resume the saved target and progress. Do not repeat completed migrations or recreate retired members. Require a reverse migration for rollback. | Not yet tested. |

Topology updates need visible staged progress. These cases do not require
one global transaction across every Agent. Local Agents still need atomic
definition and state changes at their own upgrade boundaries.

## Validation

| Check | Result |
| --- | --- |
| Focused upgrade examples, seed 0 | 9/12 pass; three enabled acceptance failures; no skips. |
| Separate full example selection, seed 0 | 272/283 pass; the same 11 acceptance failures; no skips. |
| Full suite with examples, integration, flaky tests, and coverage, seed 0 | 1148/1159 pass; 11 recorded acceptance failures; one existing approved DIST-03 exclusion. |
| Coverage | 84.8%; above the 80% floor. |
| Formatting, compilation with warnings as errors, required Credo warning check, and Dialyzer | Pass with `mix quality`; zero Dialyzer errors or skips. |
| Documentation with warnings as errors | Pass. |
| Local documentation links and whitespace | Pass. |
| Local Hex package build | Blocked by the existing local-path jido_action dependency. |

The full suite command was:

```sh
mix test --include example --include integration --include flaky --seed 0 --cover
```

The full suite has no additional failures beyond the recorded acceptance
gaps. The only excluded test is the existing approved DIST-03 check. The
runtime is Elixir 1.20.3 and OTP 29. The Elixir 1.18 / OTP 27 floor was not
tested in this pass. Core source, design proposals, and dependencies are
unchanged. The package check published nothing.

The [first feature pass](feature-acceptance-results.md) has 33 checks with
eight existing failures. This pass adds 12 checks and three further failures.
It does not change those earlier acceptance targets.
