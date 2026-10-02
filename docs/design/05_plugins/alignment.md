# Plugin alignment

## Current review status

On 2026-10-01, the user selected one Plugin module with optional callbacks
([GAP-018](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/GAP_ANALYSIS.md#gap-018)).
The separate authoring-module design is superseded. Internal owner manifests
remain implementation metadata. Ordinary modules can receive delegated work
without becoming new public Plugin roles. Current code already implements
this shape; no declaration migration or facet-authoring cleanup is required.
The complete document remains Pending approval.

GAP-019 is corrected in the design: `vsn`, `option_keys`, callback selection,
and live option validation describe the current API. GAP-020 is corrected
under the selected live/durable policy: load input is portable; reconstructed
output is checked against the live state schema. PLG-REQ-017 is retired because
it applied a durable restriction to live reducer output.

The user selected GAP-021: an implemented `after_commit/3` hook is required
before Directives. Failure stops later effects and preserves the commit and
caller result. The [owner design](design.md#required-after-commit-notification)
defines the input, order, operation limit, failure, and non-replay contract.
Commit and Server documents carry its dependent timing rules. No source
change or new test run was required for this document correction.

The user selected removal of Scheduler durable delivery in GAP-023.
The [core Scheduler contract](design.md#core-scheduler) keeps timers, mailbox
delivery, and restoration of recurring definitions. It removes saved pending
deliveries, retry workers, enqueue controls, and business acknowledgement.
The source still implements the removed feature. This is required code
cleanup; the review has not performed it.

GAP-022 is corrected here: the Scheduler contract belongs in this Plugin
design. PLG-REQ-061 through PLG-REQ-068 were recovered from commit `c2825dfb`
with the same intent. PLG-REQ-069 through PLG-REQ-076 are explicitly retired
under GAP-023. Delivery's Plugin ledger now lists the declared active IDs
and separates the retired IDs.

## Current evidence

| Source | Evidence |
| --- | --- |
| `lib/jido/agent/plugin/pipeline.ex` | The evaluator `run/5` path protects state, validates each Directive once, and reduces owned state. |
| `lib/jido/agent/plugin.ex` | The Agent facet reads complete state during preparation and returns one portable input. |
| `lib/jido/agent/runner.ex` | The Runner exposes isolated `prepared` and `runtime` slots without changing the source Signal. |
| `lib/jido/agent_server/plugin.ex` | Admission receives a read-only value and returns only its package runtime input. |
| `lib/jido/plugin.ex`, `lib/jido/agent_server/plugin/commit.ex`, `lib/jido/agent_server/post_commit.ex` | Hook declaration, exact read-only committed view, ordered owned tasks, and failure handling. |
| `test/jido/agent_server/after_commit_test.exs` | Existing cases cover exact revisions, equal state, stateless input, order, failure, timeout, reentry, and shutdown. Inspected during review; not rerun. |
| `test/jido/plugin/preparation_test.exs` | Full-state reads, pure input, reduction, direct and live parity, rejection, and portability pass. |
| `test/jido/plugin/contract_test.exs` | Owned-state protection, Directive validation, and reducer isolation pass. |
| `test/jido/plugin/ordering_test.exs` | State reducers run in declaration order and stop at the first error. |
| Core test suite | The package suite checks owner facets, examples, and runtime boundaries. |

## Gap register

| Gap | Owner | State |
| --- | --- | --- |
| One module with callback-derived capability groups | Plugin declaration | Selected; current implementation retained |
| Required after-commit notification | Plugin and live commit | Selected; design and dependent timing corrected |
| Scheduler durable delivery removal | Core Scheduler | Selected; source, tests, and guide cleanup pending |
| Scheduler requirement ownership | Plugin design and delivery ledger | Corrected; retained and retired IDs are explicit |
| Bundled Plugin migration | Plugin packages | Complete |
| Identity and Secure Signal use package inputs without Signal replacement. | Examples | Fixed |

## Ordered follow-up

1. Keep each Plugin in one module with optional owner callbacks.
   Ordinary internal delegation is permitted; separate authoring facets are removed.
2. Keep custom Directive validation on its Directive module.
3. Remove Scheduler durable delivery and its public enqueue/acknowledgement
   API, owned pending fields, and delivery-only options. Clean up affected
   guides, examples, fixtures, and tests. Preserve one-shot delivery, future
   recurring timers, saved recurring definitions, and optional occurrence metadata.
4. Verify the saved-definition boundary before removing pending-delivery fields
   from checkpoint compatibility. Record how old delivery-mode definitions are handled.
5. Run appropriate package format, compile, and test checks after code removal.

The removal scope includes `Scheduler.Durable`, `Delivery`, `Enqueue`,
`Signal.Enqueue`, `Queue`, and `Acknowledge`; `delivery: :durable`,
`admit_occurrence/2`, `acknowledge/1`, `delivery_interval`, and
`delivery_timeout`; and pending fields in the Scheduler state and runtime.
Timer reconciliation retry, wall-clock handling, and occurrence metadata are
separate from pending business redelivery and need their existing checks.
Shared Bus acknowledgement and generic application recovery examples are
outside this Scheduler removal decision.

## Acceptance matrix

| Requirement | Evidence |
| --- | --- |
| `PLG-REQ-011` to `PLG-REQ-017` | Agent schema and Plugin contract tests |
| `PLG-REQ-018`, `PLG-REQ-021` to `PLG-REQ-029` | Preparation and admission contract tests |
| `PLG-REQ-031`, `PLG-REQ-032`, `PLG-REQ-035` | Plugin ordering and validation tests |
| `PLG-REQ-036` to `PLG-REQ-039` | Directive ownership and runtime tests |
| `PLG-REQ-040` to `PLG-REQ-051` | Agent Server commit and Plugin lifecycle tests |
| `PLG-REQ-053` to `PLG-REQ-060` | Persistence and Topology facet tests |
| `PLG-REQ-077` to `PLG-REQ-084` | `after_commit_test.exs` and the hook implementation named above |
| `PLG-REQ-061` to `PLG-REQ-068` | Occurrence, one-shot, and recurring runtime cases; retained behavior to verify after removal |
| `PLG-REQ-085` to `PLG-REQ-088` | Required evidence after removal: OTP delivery, restore future timers, no missed-tick replay, and no business acknowledgement requirement |
