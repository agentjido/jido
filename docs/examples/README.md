> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# Jido example catalog

This directory is a research backlog and an architecture pressure test for Jido
V3. It does not define a new public API.

Start with the [normalized catalog](catalog.md). It is the one master list of
examples. Each row links to one small profile under `profiles/`.

## Current implementation

The main catalog has 47 current feature profiles. Basic has five matching source
and test folders with 22 [SDK integration tests](../../test/examples/01_basic/README.md).
See [current Basic results](basic-results.md) for verification and the schema
fix. The ten old Basic profiles remain in [the research archive](archive/basic).
The [historical catalog results](implementation-results.md) describe the
original 100-profile pass.

Workflow has nine matching source and test folders with 35
[SDK integration tests](../../test/examples/02_workflow/README.md). Its 17 old
domain profiles remain in the [Workflow archive](archive/workflow/README.md).
See [current Workflow results](workflow-results.md).

LLM has ten matching source and test folders with 66
[SDK integration tests](../../test/examples/03_llm/README.md). Each adds one
capability, from a typed model response through child Agents and recursive
analysis. See the [LLM results](llm-results.md) and [archive](archive/llm/README.md).

Runtime has 13 fixtures and 93 passing tests. Multi-agent has six fixtures and
38 passing tests. The promoted examples include observability, recovery, remote
child placement, and remote lifecycle. The
[persistence fix](persistence-write-results.md) rejects stale durable writes.
Research now contains eight unresolved capability questions. See the
[capability ledger](research-capabilities.md).
DIST-01 now has a working remote-child example and 16 passing core tests; see
the [implementation results](dist-01-results.md).
OBS-01 now has [nine passing core tests and an observer example](obs-01-results.md).
[OBS-02](obs-02-results.md) has 12 tests for work/result traces and creation
causes through startup, retry, failure, restore, and local/remote restart.
REC-01 has an [explicit delivery Plugin](rec-01-results.md): 11 passing tests
prove saved intent, restart, duplicate delivery, and committed confirmation.
[DIST-02](dist-02-results.md) adds four passing remote lifecycle tests, and
[DIST-03](dist-03-results.md) proves cross-node restore and revision fencing,
then pauses at cluster-wide ownership authority.
[REC-02](rec-02-results.md) adds seven passing pending-job recovery tests.
[REC-03](rec-03-results.md) has 25 passing identity and recovery tests. Durable
schedules save pending work, retry it after restore, and commit acknowledgement
with the business result. The declared policy skips other busy or offline slots.
The [persistence boundary probes](persistence-boundary-results.md) add six passing
controls and three enabled failures for loaded identity, loaded portability,
and admission after an uncertain write. They use no database or VM restart.

Topology adds five fixtures for independent Agents, logical ownership, a Bus
swarm with 1000 workers, keyed account Agents, and a composed two-team system. Spark DSL, Builder, and JSON
produce the same definition and execution plan. See the
[Topology guide](../../lib/examples/07_topology/README.md) and
[spike results](topology-results.md).

## Catalog rules

Factory adds four examples using ReqLLM directly: live conversation, a
three-Agent system with IEx chat, a factory with four department heads, and a
larger Flow across nine workers with parallel review and bounded repair.
See the [Factory guide](../../lib/examples/06_factory/README.md) and
[orchestrator plan](../../lib/examples/06_factory/orchestrator-plan.md).

The current feature sequence is ordered by learning dependencies. Each profile
maps to one code feature group:

| Category folder | Example count |
| --- | ---: |
| `01_basic` | 5 |
| `02_workflow` | 9 |
| `03_llm` | 10 |
| `04_runtime` | 13 |
| `05_multi_agent` | 6 |
| `06_factory` | 4 |
| `07_topology` | 5 |
| `99_research` (unresolved queue) | 8 |

Current examples use `CC_EE_name`. `CC` is the category number. `EE` is the
example number within that category. Both numbers have two digits. The
`99_research` sorts last and contains unresolved capability questions only.
The example numbers follow the feature order within each category. The first example is
`01_01_minimal_agent`.

The same ID appears in all three locations:

- `lib/examples/01_basic/01_01_minimal_agent/`
- `test/examples/01_basic/01_01_minimal_agent/`
- `docs/examples/profiles/01_basic/01_01_minimal_agent.md`

Use the next number within a category for a new example. Keep existing IDs
stable unless the catalog order is deliberately revised. Runtime and Multi-agent
were revised on 2026-09-04. Historical profiles stay under `archive`; their old
source remains available in Git history.

Complexity level 1 is the smallest example. Level 5 is a large or durable
system. The feature group is separate from the complexity level.

The profile status has one of these values:

- `proposed`: Jido can support the example with current public contracts.
- `implemented`: a local implementation exists and its current tests pass.
- `failed burn-in`: an implementation exists, but one or more stated profile
  contracts fail. The profile or burn-in report records the gap.
- `doesn't work yet`: a local code spike exists, but the complete profile is
  incomplete. The profile distinguishes an SDK contract gap from example work
  that has not been implemented.
- `blocked by current Jido`: the example needs a missing public contract.
- `future`: the example is useful, but it is not an early architecture test.

The original profile test class is either `local deterministic` or `true integration`.
These labels describe external dependencies. Local SDK tests are integration
tests too. All six feature groups use real SDK components with deterministic
test controls. A local deterministic test uses fixtures, a fake clock, an in-memory adapter, or a fake
model. A true integration test uses a live network, model, browser, database,
cluster, or media service.

## Jido user model used by every profile

One Signal selects one Action or Flow. The Action or Flow can call external
systems. Tests inject deterministic adapters for this work when possible. The
Action or Flow returns one complete next Agent state, and the Agent Server
commits that state one time.

Directives are commands for runtime state and post-commit runtime work. Typical
uses are Signal delivery, scheduling, child lifecycle, subscriptions, and work
owned by a Plugin runtime. A Directive does not replace domain state changes.

This catalog does not require an effect-free Turn. It does require a clear
commit boundary. If an Action or Flow performs an irreversible effect before
commit, the example must state its idempotency and retry rules.

## Supporting files

- [Capability ledger](research-capabilities.md) records solved capabilities and
  the eight items that remain in the research queue.
- [Runtime and Multi-agent feature results](runtime-multi-agent-results.md) records
  the current feature sequence, local SDK evidence, and full-suite results.
- [Gap register](runtime-multi-agent-gaps.md) separates SDK limits, application
  work, adapter work, scale targets, and fixture failures.
- [Research map](runtime-multi-agent-research.md) accounts for all 54 old profiles
  and maps them to current examples or unresolved capabilities.

- [Example interface review](example-interface-results.md) records command naming,
  generated interfaces, and the custom preparation that remains.

- [Inline Actions and expressions](inline-actions-expressions-results.md)
  records the beta.6 dependency, Agent route syntax, expanded Flow slots,
  `Jido.Expr`, and current validation.
- [Historical inline Step adoption](inline-step-results.md) records the earlier
  beta.5 probe.
- [Agent DSL migration results](agent-dsl-results.md) records the Spark syntax
  conversion across the catalog and integration examples.
- [Workspace checkpoint](checkpoint.md) records the committed work, current
  validation, and remaining test and quality findings.
- [Agent-owned history](agent-history.md) records the Thread Plugin removal and
  the migration to ordinary Agent state.
- [Research sources](research-sources.md) records official sources and access
  dates.
- [Pi package ecosystem](pi-package-ecosystem.md) maps the Pi package catalog
  and extension model to focused Jido pressure tests.
- [Basic SDK results](basic-results.md) records the current 22 integration
  cases and the SDK validation fix.
- [Workflow SDK results](workflow-results.md) records nine fixtures for graph
  execution, effects, collections, composition, and approval.
- [Runtime timing and recovery results](runtime-results.md) records timer,
  persistence, ReAct failure, and durable schedule pressure.
- [RLM stress results](rlm-results.md) records recursive execution, shared work
  limits, cancellation, and concurrent Agent runs over a local corpus.
- [Framework source coverage](source-coverage.md) maps every researched
  framework to representative normalized profiles.
- [Test strategy](test-strategy.md) defines the local and live test boundary.
- [Implementation waves](implementation-waves.md) gives the recommended build
  order.
