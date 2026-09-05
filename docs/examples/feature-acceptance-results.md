# Feature acceptance results

> This report records the first ten probes. The later
> [live-upgrade pass](live-upgrade-results.md) adds three examples with 12 tests:
> nine pass and three fail. Current combined research totals are 34/45 passing,
> with 11 enabled failures across nine proposed core contracts.

Date: 2026-09-05. Core baseline: `a23091b4` on `v3-spike`.

Ten examples exercise the features selected in the design discussion. The
focused run has **33 checks: 25 pass and eight fail**. The failures identify
**six core features that need work**. Four other features work as explicit
application or runtime extensions. Core source and design proposals are unchanged.

The failed checks state desired behavior. They are enabled tests, not skipped
placeholders or tests that accept a known defect. An ordinary test exit status
of 2 is expected until all eight assertions pass.

## Run the examples

From the jido repository:

```sh
mix test test/examples/99_research/99_0{1,2,3,4,5}* test/examples/99_research/99_{09,10,11,12,13}* --include example --seed 0 --trace
```

This selection reproduces the original ten probes. To include the later
upgrade examples, run the whole test/examples/99_research directory.
Each example README has a focused command. The test file is the runnable
acceptance demonstration. There is no separate mock implementation of Agent
commit, routing, Plugin composition, or runtime recovery. Controlled external
services belong to the example. Every test selects real public Jido APIs.

## Results

| ID | Feature | Pass | Fail | Classification |
| --- | --- | ---: | ---: | --- |
| FA-01 | [Route precedence and fixed selection](../../lib/examples/99_research/99_09_route_selection/README.md) | 2 | 2 | Core feature required |
| FA-02 | [Plugin read and prepared-input isolation](../../lib/examples/99_research/99_10_plugin_isolation/README.md) | 2 | 2 | Core feature required |
| FA-03 | [Stable Agent references and durable namespace identity](../../lib/examples/99_research/99_11_stable_reference/README.md) | 2 | 1 | Core feature required; application reference works |
| FA-04 | [Definition revision checks on restore](../../lib/examples/99_research/99_12_definition_revision/README.md) | 1 | 1 | Core feature required |
| FA-05 | [Durable deletion](../../lib/examples/99_research/99_13_durable_delete/README.md) | 2 | 1 | Core feature required |
| FA-06 | [Plugin runtime reconstruction from committed state](../../lib/examples/99_research/99_03_input_resource_lifecycle/README.md) | 1 | 1 | Core feature required; public pull recovery works |
| FA-07 | [Progress observation with recovery](../../lib/examples/99_research/99_01_progress_observation/README.md) | 5 | 0 | Works as an application extension |
| FA-08 | [Acknowledged handoff and worker reconciliation](../../lib/examples/99_research/99_04_handoff_reconciliation/README.md) | 3 | 0 | Works as an application protocol |
| FA-09 | [Shared work budgets](../../lib/examples/99_research/99_05_capacity_deadlines_cleanup/README.md) | 3 | 0 | Works as a local runtime extension |
| FA-10 | [Fenced distributed ownership](../../lib/examples/99_research/99_02_distributed_authority/README.md) | 4 | 0 | Works with an explicit external authority |

## Core features to add

| Contract | Failing observation | Acceptance target |
| --- | --- | --- |
| FA-01a: Route precedence | Exact, wildcard, and fallback routes return three matches and a RoutingError. | Select the highest-ranked match. |
| FA-01b: Fixed executable | Preparation changes the handler from create to cancel. | Select from the source Signal before preparation. |
| FA-02a: Plugin read projection | The audit callback can read customer_secret and all state fields. | Supply only declared observed fields. |
| FA-02b: Prepared input ownership | A later Plugin replaces original with replaced. | Isolate each Plugin's prepared input. |
| FA-03: Durable namespace identity | The same logical reference cannot thaw under a replacement local instance; it returns not_found. | Use canonical namespace, partition, and Agent ID across storage and runtime. |
| FA-04: Definition revision | A revision-1 checkpoint restores under revision 2. | Require an exact definition revision match. |
| FA-05: Durable deletion | A delayed revision-0 writer recreates a deleted order. | Retain and enforce a conditional deletion record. |
| FA-06: Fresh runtime Init | Replacement Init contains no committed Plugin state or state version. | Supply a current, matching state/version pair. |

These are missing proposed contracts. This report does not claim that current
behavior violates the implemented v3-spike API. The existing write-ownership
checks and current recovery mechanisms remain useful and have passing controls.

## Evidence and scope

### FA-01: Route precedence and fixed selection

**Observed:** A single route works in direct and live execution. The fallback handles an unrelated Signal. An exact route plus wildcards returns a RoutingError with three targets. A preparation Plugin changes the selected handler from create to cancel.

**Required work:** Select the first route by Router precedence from the source Signal. Keep that executable fixed through Plugin preparation.

**Proof limit:** The probe uses three explicit Agent DSL definitions and cmd/3. Route defaults and the preparation Plugin are declared in the DSL. It does not replace routing with an example-owned dispatcher.

[Runnable source](../../lib/examples/99_research/99_09_route_selection/route_selection.ex) · [Acceptance tests](../../test/examples/99_research/99_09_route_selection/route_selection_test.exs)

### FA-02: Plugin read and prepared-input isolation

**Observed:** Owned Plugin state updates successfully. An Action cannot overwrite it, and failure preserves live state. However, the audit callback receives customer_secret and the complete state. A later Plugin replaces the first Plugin's prepared input.

**Required work:** Add an observed-field declaration, bounded callback data, and separately owned prepared input. Preserve the existing write protection.

**Proof limit:** The intended audit projection is total only. Current core has no observes declaration. The enabled assertion marks that missing contract; the example does not claim to configure an existing isolation option. Callback isolation is an API contract, not a sandbox for untrusted BEAM code.

[Runnable source](../../lib/examples/99_research/99_10_plugin_isolation/plugin_isolation.ex) · [Acceptance tests](../../test/examples/99_research/99_10_plugin_isolation/plugin_isolation_test.exs)

### FA-03: Stable Agent references and durable namespace identity

**Observed:** An application reference survives persistent process replacement. Equal IDs in separate namespaces remain isolated. Rebinding the same namespace to a new local Jido instance makes thaw return not_found because storage identity contains the old instance name.

**Required work:** Use one canonical namespace, partition, and ID value in live addressing and persistence. Add the proposed Ref facade without requiring a saved PID.

**Proof limit:** StableReference is an example-owned struct. Local lookup uses the current public Jido.whereis_agent/3 and AgentServer API. The passing controls do not establish a core Ref API. Storage uses the controlled in-memory byte adapter.

[Runnable source](../../lib/examples/99_research/99_11_stable_reference/stable_reference.ex) · [Acceptance tests](../../test/examples/99_research/99_11_stable_reference/stable_reference_test.exs)

### FA-04: Definition revision checks on restore

**Observed:** A matching cart definition restores total 20. After the same module changes from revision 1 to revision 2, restore still succeeds and returns metadata for revision 2.

**Required work:** Save and enforce a positive module-owned definition revision. Reject a mismatch before restoration, even when saved state still passes its schema.

**Proof limit:** Core has no definition_revision option. The probe declares the intended revision in module metadata and a function. It recompiles only its isolated Cart module in a serial test. It does not implement automatic state migration.

[Runnable source](../../lib/examples/99_research/99_12_definition_revision/definition_revision.ex) · [Acceptance tests](../../test/examples/99_research/99_12_definition_revision/definition_revision_test.exs)

### FA-05: Durable deletion

**Observed:** Existing revisions reject a stale writer. Deletion makes an order unavailable. A delayed initial writer then succeeds with expected_revision 0 and recreates the deleted record.

**Required work:** Retain a tombstone and update lifecycle state with compare-and-swap. Reject old writers across deletion and reactivation boundaries.

**Proof limit:** The example uses public persistence APIs and an atomic in-memory byte adapter. It proves loss of revision history after deletion. It does not define tombstone retention or physical purge policy.

[Runnable source](../../lib/examples/99_research/99_13_durable_delete/durable_delete.ex) · [Acceptance tests](../../test/examples/99_research/99_13_durable_delete/durable_delete_test.exs)

### FA-06: Plugin runtime reconstruction from committed state

**Observed:** The input runtime automatically pulls current owned state after startup. After a crash it rebuilds feed B, rejects stale feed A input, and closes owned resources. Replacement Init itself has no plugin_state or state_version.

**Required work:** Supply current committed owned state and its matching version in each replacement Init. Retain the working public recovery path.

**Proof limit:** This tests Plugin runtime loss, input generation checks, and resource cleanup. It does not test a live vendor connection or duplicate event IDs. Jido.Plugin.state/1 already supplies a working application recovery mechanism.

[Runnable source](../../lib/examples/99_research/99_03_input_resource_lifecycle/runtime_reconstruction.ex) · [Acceptance tests](../../test/examples/99_research/99_03_input_resource_lifecycle/runtime_reconstruction_test.exs)

### FA-07: Progress observation with recovery

**Observed:** Waiting reasons are queryable. Ten live progress updates retain only three events, while committed state stays unchanged. Observer loss does not fail work. Cancellation stops active evaluation. A terminal result survives Agent persistence and observer replacement.

**Required work:** No core feature is required for this proof. Keep application progress and bounded retention outside AgentServer.

**Proof limit:** The buffer has one producer and demand-based reads. It sends no queue of notifications to slow consumers. Agent state stores terminal results; it does not persist transient progress. Persistence recovery uses an in-memory test adapter, not a fresh VM or database.

[Runnable source](../../lib/examples/99_research/99_01_progress_observation/progress_observation.ex) · [Acceptance tests](../../test/examples/99_research/99_01_progress_observation/progress_observation_test.exs)

### FA-08: Acknowledged handoff and worker reconciliation

**Observed:** Real child Agents acknowledge transfer. The coordinator rejects stale and duplicate results. An unavailable recipient leaves the old owner. Recipient loss clears the pending offer, and explicit reconciliation starts a replacement with a new generation. Parent shutdown removes children.

**Required work:** No core feature is required for this proof. Keep request authority, acknowledgements, generations, and desired worker policy in application state.

**Proof limit:** There is one request and one live coordinator. The tests cover recipient loss, not durable coordinator loss or arbitrary network partitions. The coordinator controls accepted results; external effects require their own fencing.

[Runnable source](../../lib/examples/99_research/99_04_handoff_reconciliation/handoff.ex) · [Acceptance tests](../../test/examples/99_research/99_04_handoff_reconciliation/handoff_test.exs)

### FA-09: Shared work budgets

**Observed:** Concurrent teams share two active slots and two queue slots. A fifth submission is rejected. Expired queued work never starts. Worker loss releases capacity. Normal service shutdown stops all monitored job Agents, Actions, call Tasks, and the Task supervisor.

**Required work:** No core feature is required for this proof. The application admission service owns the shared budget and uses public Jido lifecycle APIs.

**Proof limit:** Defaults are eight active jobs and 32 queued jobs; tests use two of each to force contention. Limits apply to accepted jobs, not raw BEAM mailbox messages or every internal process. Hard loss of the budget service, durable budgets, and arbitrary deep trees remain outside this proof.

[Runnable source](../../lib/examples/99_research/99_05_capacity_deadlines_cleanup/shared_budget.ex) · [Acceptance tests](../../test/examples/99_research/99_05_capacity_deadlines_cleanup/shared_budget_test.exs)

### FA-10: Fenced distributed ownership

**Observed:** Two Erlang nodes run real inventory Agents. Replacement fences old admission before Action work. Storage and the sink reject stale tokens. Authority loss rejects work. A disconnected old owner remains fenced after reconnection.

**Required work:** No core feature is required for this controlled proof under the current admit callback and persistence adapter. Preserve an authority check before Action work if the proposed Plugin API removes admit/3.

**Proof limit:** The external authority is a controlled GenServer, not a consensus service or production lease provider. Claim, byte writes, and sink checks serialize there. Core-only exclusive activation remains unsupported; the existing skipped DIST-03 test is unchanged. The disconnect test blocks automatic reconnection with a temporary peer cookie change.

[Runnable source](../../lib/examples/99_research/99_02_distributed_authority/fenced_inventory.ex) · [Acceptance tests](../../test/examples/99_research/99_02_distributed_authority/fenced_inventory_test.exs)

## Example defects corrected during the pass

The shared-budget service initially missed cleanup on supervisor shutdown.
The service now traps exits so its terminate callback closes the job Agents
and call Task supervisor. Its process-monitor acceptance test passes. This
was an example defect, not a core feature gap.

An initial Builder-based version hit four opaque-type Dialyzer warnings.
The fixed Agent definitions now use the Agent DSL: agent, routes, and plugin
declarations. Route and Plugin variants select separate DSL modules. The
revision test also compiles a DSL definition. Runtime reconstruction adds the
test observer PID to the declared Plugin's options through a public constructor;
that runtime value is supplied after the static definition is compiled.

The [DSL validation run](dsl-acceptance-output.txt) covers all 45 research
checks, including the later upgrade cases. It retains 34 passing checks and
the same 11 acceptance failures. No acceptance assertion was changed.

## Validation

| Check | Result |
| --- | --- |
| Focused research selection, seed 0 | 25/33 pass; eight enabled acceptance failures; no skips. |
| Separate full example selection, seed 0 | 263/271 pass; the same eight acceptance failures; no skips. |
| Full suite with examples, integration, flaky tests, and coverage, seed 0 | 1139/1147 pass; the same eight acceptance failures; one existing approved DIST-03 exclusion. |
| Coverage | 84.8%; above the 80% floor. |
| Compile with warnings as errors | Pass. |
| Required Credo warning check | Pass: `mix credo --strict --only warning`. |
| Dialyzer | Pass; zero errors or skipped warnings. |
| Docs with warnings as errors | Pass. |
| Formatting and whitespace | Pass. |
| Local documentation links | 23 files checked; no broken links. |
| Hex package build | Blocked by the existing local-path `jido_action` dependency. No dependency change was made. |

The full suite command was:

```sh
mix test --include example --include integration --include flaky --seed 0 --cover
```

The full suite has no additional test failures beyond the eight feature
assertions recorded above. Existing negative-input tests emit compiler type
warnings under Elixir 1.20.3. The separate production compile passes with
warnings as errors. Broad `mix credo --strict` also reports style and design
findings; the repository's required warning-only check passes.

The runtime used is Elixir 1.20.3 and OTP 29. The declared Elixir 1.18 / OTP 27
floor was not tested in this pass. The Hex check ran locally and published
nothing.

[Focused run output](feature-acceptance-output.txt) retains the test names,
assertion failures, and final counts. No core source or design proposal was
changed to make an example pass.
