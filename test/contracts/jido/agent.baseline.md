# Agent contract baseline

Date: 2026-10-15. Component: `jido.agent`.

The rollout protects 25 public obligations with 76 contract tests. It covers
authoring, canonical definitions, independent instances, and direct commands.
The public DSL syntax is unchanged. The rollout made no library changes and
did not change AgentServer. Earlier local Agent and Topology edits remain
outside the rollout change set.

Development and tests use the sibling Covenant fork on `feat/macro-mutation`,
checkpoint `72609acff92ed82da69a640100c35159323e2df0`. The earlier full mutation
run used `245f0bfed5cffd3cfb59e14c31fad47dc126fa8c`. The fork is not published by
this rollout. A CI checkout must supply the sibling path dependencies.

## Current focused checks

| Check | Result |
| --- | --- |
| `mix test.contract` | 76 passed; 25/25 active obligations have passing tests |
| Agent unit tests and authoring property test, seed 0 | 231 passed; 1 longer fuzz test excluded |
| Three selected mutants, without fail-fast | 3 killed; exact test attribution; no invalid mutants or timeouts |
| Saved mutation evidence audit | 257 annotations match historical survivors; only the three addressed gaps have no annotation |
| Source and test audit | All 220 saved library and contract/support file hashes still match |
| Format, compile with warnings as errors, and documentation | Passed |
| Configured lint gate: `mix credo --strict --only warning` | Passed; no issues |

The focused mutation command was:

```sh
MIX_ENV=test mix covenant.mutate jido.agent --macros \
  --only m0684,m0985,m1034 --jobs 1 --seed 0 --timeout 5000 \
  --max-runtime 120000 --out tmp/covenant/agent-focused.json
```

Each mutant ran against all 76 contract tests. The original tests passed before
and after mutation. The report identifies a focused selection of 3 from 1,302
mutants and defers 257 annotations outside that selection.

| Mutant | Site and change | Added assertion |
| --- | --- | --- |
| `m0684` | `Jido.Agent.Extension.route_target/1`: replace a tuple route target with nil | Reject an invalid extension-owned target with route defaults, as well as a bare target |
| `m0985` | `Jido.Agent.State.initialize/2`: disable default parsing | Reject invalid static defaults when nil state triggers initialization |
| `m1034` | `Jido.Agent.State.validation_only_schema/1`: remove `:inner` traversal | Reject input conversion inside array and map-set schemas |

These are test gaps found by mutation review. Their assertions now kill the
same exact sites, operators, and changes. They have no accepted-survivor entry.

## Earlier complete mutation run

The completed review run used the 20 implementation files listed in
`agent.obligations.md`, macro mode, seed 0, a 5,000 ms test timeout, eight
workers, and full attribution. It had a passing baseline of 76 tests. This run
preceded the three assertion additions above.

| Verdict | Count |
| --- | ---: |
| Killed | 942 |
| Survived | 260 |
| Invalid | 100 |
| Timeout | 0 |
| Total | 1,302 |

The historical raw kill score was 78.37%: 942 of 1,202 valid mutants. Invalid
mutants receive no kill credit. This was not a passing reviewed gate: all 260
survivors were initially unsorted.

Review classified 257 survivors in `agent.survivors.yml`: 201 `unpromised`,
37 `equivalent`, and 19 `dead-code`. Each entry names an exact site, operator,
change, and reason. The audit confirms that every entry matches one historical
survivor. No entry accepts a timeout or evaluation gap. The remaining three
survivors exposed the test gaps listed above.

The second full run was cancelled. Its partial checkpoints are not complete
evidence. The full 1,302-mutant profile was not rerun after the final assertion
changes. The focused result confirms the three fixes; it does not recheck the
257 deferred annotations or supply a new full-profile score. Keep these two
results separate. Run the full profile at a later stable checkpoint when needed.

## Full-suite test and coverage evidence

The last full normal-category run included core, property, benchmark, example,
authoring, local system, and peer tests, with seed 0 and four test cases at once:

```sh
mix coveralls.json --preload-modules \
  --include bench --include example --include authoring --include system \
  --include flaky --include peer --include property --seed 0 --max-cases 4
```

It passed 2,556 tests, with two existing skips and 161 exclusions. This rollout
added no skips. It did not run opt-in external services or the longer fuzz suite.
The saved library, contract test, and compiler support hashes still match that
run. The current focused tests also pass with the committed Covenant fork.

| Coverage scope | Hit lines | Executable lines | Coverage |
| --- | ---: | ---: | ---: |
| Package | 9,110 | 9,772 | 93.23% |
| 20 Agent mutation-profile files | 847 | 859 | 98.60% |

Coverage came from `cover/cov.json`. It is line coverage, not mutation coverage.
The existing 90% package gate remains active. The earlier `mix test.ci` check
also passed: 1,531 core/property tests, then 76 contract tests. The final three
assertion additions were included in the later full coverage run.

The local runtime was Elixir 1.20.4 / OTP 29.1. The declared Elixir 1.18 /
OTP 27 floor was not checked in this rollout.

## Tool and check limits

The Spark provider file `lib/jido/agent/dsl/extension.ex` is outside the mutation
profile. A malformed provider attribute made an asynchronous Spark
`after_verify` callback terminate a Covenant worker without an invalid verdict.
The incomplete 21-file attempt supplies no full mutation result. Fresh DSL
compilation and line coverage still test the provider's public behavior.

The ordinary `Jido.Agent.DSL.Generator.function/3` function returns quoted code.
The mutation tool does not enter that quote. Explicit tests cover generated
helpers. Generic mutation operators do not produce every possible semantic
fault. Property tests and fixed cases remain necessary.

The earlier `mix quality` attempt stopped at nine Dialyzer findings: two in the
sibling `jido_action` authoring compiler and seven generated inline Action
`to_json/0` contracts in Jido examples and a remote-child fixture. These were
outside this rollout's Agent contract changes. They were not suppressed or
fixed. The full quality command is not reported as passing.

Jido's required lint gate is `mix credo --strict --only warning`. Broader
`mix credo` and `mix credo --strict` checks also ran during closeout. They failed
on readability, refactoring, and design suggestions across the repository,
including test-fixture style suggestions. Those broader checks are not part of
the configured gate. This rollout does not claim that all lint categories pass.

## Local evidence files

Large mutation matrices and coverage artifacts remain ignored local files.
Their SHA-256 digests identify the evidence used in this report:

| File | SHA-256 |
| --- | --- |
| `tmp/covenant/agent-review-profile.json` | `6efd52bc411c6a2e17f1e01a1151bf198960b7fcf7cc88c378f420c8da4c9950` |
| `tmp/covenant/agent-focused.json` | `e2a759ab30421f218c3753bb54edf9a76ee72dc32215a65fdc97746faa3cfecf` |
| `agent.survivors.yml` | `80ac5454f1074d4a82964574ebbcf8ed6e4be61ea1e9c2a2069d6214daf172d0` |
| `cover/cov.json` | `a30a11af7c0c545bf9de451ccf7ce41b4a387cd9c0192cf6324c8135018c732d` |

`tmp/covenant/agent-rollout-evidence.json` records the evidence audit and keeps
the historical full run separate from the current focused run. It does not
merge verdicts or claim a passing current full-profile gate.

## Agent and Topology DRY refinement — 2026-10-15

The pass from `e578c829` is recorded in the
[Topology baseline](topology.baseline.md#agent-and-topology-dry-refinement--2026-10-15).
It gives the five changes, exact commands and selected sites, annotation audit,
and separate manual regression evidence. The contract gate passes 122 tests
across all 42 obligations. All 19 focused Covenant sites are killed. Both
manual regressions failed with the old bodies and passed after source
restoration. The combined run passes 2,097 tests with 92.4% package line
coverage. Format, compilation with warnings as errors, and warning lint pass.
Dialyzer retains the same ten existing warnings. The full historical mutation
profile was not rerun.

## Shared code reduction — 2026-10-15

The next Agent/Topology pass removes 68 net library lines. Shared map decoding
keeps the Agent and Topology error rules and recursive value handling. The
Agent contract now has 81 tests. The final gate passes all 125 tests and all
42 obligations. The combined suite passes 2,100 tests with 92.4% line coverage.

Three focused shared-Data mutations run through all 81 Agent contract tests.
All three are killed with exact attribution and no invalid mutants or timeouts.
The Topology checks and six separate semantic probes also pass. The earlier
full 1,302-mutant run was not repeated.

The ledger retains 219 exact historical entries: eight locations moved, and
one entry for the removed registration wrapper was retired. No judgments or
survivor exceptions were added. The historical verdicts were not rerun.
See [the Topology record](topology.baseline.md) for commands, exact sites,
source restoration, and evidence hashes.

## Remaining authoring reductions — 2026-10-15

Items 1–15 remove 143 net library lines and both internal Deriver modules.
The final gate passes 84 Agent and 45 Topology tests across all 42 obligations.
The combined suite passes 2,104 tests, with 51 existing exclusions and 92.4%
package line coverage. Nine Agent mutations, nine Topology mutations, and
one shared Registry-profile mutation are killed with exact attribution.
A separate initialization omission probe also fails its public guard and
passes after exact source restoration; it receives no Covenant kill credit.

The ledger retains 215 exact historical decisions and retires four changed or
removed sites. No new exemption was added. Format, forced compilation, and
warning lint pass. Dialyzer retains the same ten known findings. The full
1,302-mutant run was not repeated. See the [Topology record](topology.baseline.md#remaining-authoring-reductions--2026-10-15)
for exact commands, sites, source restoration, and evidence hashes.

## Final local reductions — 2026-10-16

Agent lowering now returns its generated code directly. Both authoring paths
use the shared indexed source-location walk. Registry bang construction uses
the common result unwrap helper. The existing public DSL remains unchanged.

The focused Agent profile kills three selected mutations. A second profile
adds Registry and kills its selected bang-result mutation. Topology separately
checks both shared source-path mutations. All selected results have exact
attribution, without invalid mutants, survivors, timeouts, or partial credit.
The earlier 1,302-mutant profile was not rerun. All 215 historical survivor
decisions remain; 12 locations move with no judgment changes. See the
[Topology record](topology.baseline.md#final-local-reductions--2026-10-16) for
exact sites, profiles, and local evidence paths.

## Explicit constructors and supported wrappers — 2026-10-16

`Jido.Agent.define/1` and `define!/1` construct neutral definitions. Generated
Agent modules expose `instantiate/0,1` and `instantiate!/0,1`. Existing `new`
and bang forms call these explicit functions with their original defaults,
results, and errors. They remain supported without deprecation warnings.
The public DSL is unchanged.

The restored-source Covenant gate passes 85 Agent and 47 Topology tests and
all 42 obligations. All eight selected Agent constructor mutations are killed
with exact attribution. The historical ledger retains all 215 decisions:
seven source locations move and 208 remain unchanged. No judgment changes.
See the [Topology record](topology.baseline.md#explicit-constructors-and-supported-wrappers--2026-10-16)
for commands, sites, evidence hashes, and package validation.

## Agent-owned composition and schedule authoring — 2026-10-16

The canonical Agent now holds optional topology intent and ordered schedule
declarations. Plain Agents have `topology: nil` and `schedules: []`. The topology
map keeps its collection shape. Agent, group, and child declarations use one
module-or-definition source rule. Root endpoints, explicit includes, imported
Agent Refs, containment, and group delivery modes remain static data.

Schedules require the Scheduler Plugin. Interval and cron declarations keep
portable Signal templates. They do not create jobs, seed Scheduler state, or
start timers. The existing JSON document format rejects the new fields when
it cannot retain them. AgentServer, AgentServer2, and legacy Topology source
files are unchanged. Runtime integration remains a later step.

Nine new obligations, I26–I34, guard this boundary. The contract gate passes
390 tests and all 145 package obligations, including all 34 Agent obligations.
The core suite passes 1,873 tests, with 1,163 existing exclusions and 92.7%
line coverage. The Agent and authoring regression selection also passed 833
tests before the final policy guard was added. The final mutation baseline
includes all 27 composition and schedule tests.

Format and compilation with warnings as errors pass. Strict lint passes for
the eight new authoring and guard files. The package warning lint check finds
one existing Logger metadata warning at `lib/jido/agent_server2.ex:2977`.
That file and its Logger configuration are unchanged.

The final focused mutation run catches all 20 selected sites, with exact
credit and no survivors, invalid mutations, timeouts, or partial credit.
The first run found two missing cases: an unrelated Plugin must not satisfy
the Scheduler requirement, and a gate command type must not be empty. Both
cases now catch their selected mutations. No survivor exemption was added.

The selected profile contains these six modules: `Jido.Agent.Authoring`,
`Jido.Agent.Codec`, `Jido.Agent.Schedules`, `Jido.Agent.Topology`,
`Jido.Agent.Topology.Reference`, and `Jido.Agent.Validation`. Its catalog has
963 sites. Catalog enumeration runs no mutations. The historical 1,302-site
profile was not rerun; no new full-profile score is claimed.

The focused command uses a temporary copy of the current obligations file,
without the historical survivor ledger. The historical ledger is checked
separately: all 215 decisions identify one current site. Only 81 source
locations move; operators, mutations, sorts, and reasons remain unchanged.

```sh
env MIX_ENV=test ERL_FLAGS='+S 4:4' mix covenant.mutate jido.agent \
  --contracts tmp/covenant/agent-authoring/contracts \
  --module Jido.Agent.Authoring --module Jido.Agent.Codec \
  --module Jido.Agent.Schedules --module Jido.Agent.Topology \
  --module Jido.Agent.Topology.Reference --module Jido.Agent.Validation \
  --test-path test/contract/jido/agent_topology_contract_test.exs \
  --test-path test/contract/jido/agent_composition_authoring_contract_test.exs \
  --only m186,m283,m296,m308,m316,m325,m342,m356,m360,m560,m593,m605,m616,m627,m667,m691,m710,m714,m715,m739 \
  --jobs 1 --seed 0 --timeout 5000 --max-runtime 300000 \
  --out tmp/covenant/agent-authoring/mutants.json
```

Local evidence stays in `tmp/covenant/agent-authoring/`. The final report
records each selected site, operator, mutation, and killing test. SHA-256:

| File | SHA-256 |
| --- | --- |
| `catalog.json` | `4f5be3679f8aec5512a1f2b13f3b93f18f42a2c3dbbd77a0654ec575ff3e3076` |
| `mutants.json` | `cb11346653b8db814cfdfc19f3b20062d42b50b3fdab0bfbe5f37ed5e9a17060` |
| `ledger-moves.json` | `f3e63fd7ded66fe66e4dc1cc245389a08d84059cc48848883496014553d7b83d` |

## Authoring review fixes F1–F7 — 2026-10-16

This pass keeps the public DSL and topology collection shape. It changes only
Agent authoring and its guards. Runtime, legacy `Jido.Topology`, and the design
Markdown files from the other thread remain unchanged. No commit was made.

- One schema-aware decoder now serves topology and schedules. It unwraps only
  optional fields that use an internal presence marker. Literal tuples and
  explicit nil, false, and zero values keep their meaning.
- Child source normalization retains the canonical neutral Agent returned by
  validation. The same rule applies to Agents, groups, children, and includes.
- Included export kinds take part in delivery validation. Known group exports
  require one or broadcast; known Agent exports reject group delivery modes.
  Unknown export kinds remain intent for the later binding boundary.
- Shared key validation, identity, and uniqueness checks replace separate
  rules. Empty and oversized atom keys fail. Atom and string aliases cannot
  bypass the self-ownership check. Schedules no longer use a topology helper.
- Source locations now include topology entries, schedules, nested bindings,
  and included maps. Spark option errors retain structured field paths. With
  compiler annotations enabled, errors use the field location when available,
  or the containing declaration location.
- Topology DSL lowering extracts authored data and locations, then calls its
  extensions. Agent extensions can lower that composition before the common
  Agent validator applies canonical rules and defaults. The earlier topology
  validation pass and repeated include subtree scans are removed.
- Group count has one conditional default. Bus kind uses the Spark fixed-field
  mechanism and the common resource schema.

Eleven new Covenant tests cover these cases. Existing obligations are refined,
and I35 adds error-location guards. The final package contract gate passes
401 tests and all 146 obligations, including all 35 Agent obligations. The
Agent and Topology unit and authoring selection passes 920 tests, with four
existing exclusions. This pass adds no skip or exclusion.

Formatting and compilation with warnings as errors pass. Strict lint passes
for the eight focused helper, topology, schedule, and guard files. Warning
lint passes for the shared compiler. Its broader strict checks retain
existing alias and complexity suggestions in unchanged code. The earlier
package lint result, including the AgentServer2 Logger warning, is unchanged.

The final focused mutation run catches all 20 selected sites from a catalog
of 866 sites. All credit is exact. There are no survivors, invalid mutations,
timeouts, or new survivor exemptions. All 38 composition and schedule guards
pass before and after mutation. The full historical 1,302-mutant profile was
not rerun. Catalog enumeration executes no mutations.

The historical ledger retains all 215 judgments. An exact-site audit moves
15 locations and changes no operator, mutation, sort, or reason.

```sh
env MIX_ENV=test ERL_FLAGS='+S 4:4' mix test \
  test/jido/agent_test.exs test/jido/agent test/jido/topology \
  test/authoring/agents test/authoring/topology --include authoring --seed 0

env MIX_ENV=test ERL_FLAGS='+S 4:4' mix test.contract

env MIX_ENV=test ERL_FLAGS='+S 4:4' mix covenant.mutate jido.agent \
  --contracts tmp/covenant/agent-authoring-refinement/contracts \
  --module Jido.Agent.Authoring --module Jido.Agent.Authoring.Compiler \
  --module Jido.Agent.Authoring.SourceMap --module Jido.Agent.Schedules \
  --module Jido.Agent.Topology --module Jido.Agent.Topology.Ref \
  --module Jido.Agent.Topology.Reference \
  --test-path test/contract/jido/agent_topology_contract_test.exs \
  --test-path test/contract/jido/agent_composition_authoring_contract_test.exs \
  --test-path test/contract/jido/agent_authoring_refinement_contract_test.exs \
  --only m011,m017,m031,m032,m035,m047,m255,m322,m327,m651,m663,m664,m665,m678,m812,m814,m817,m819,m820,m852 \
  --jobs 1 --seed 0 --timeout 5000 --max-runtime 300000 \
  --out tmp/covenant/agent-authoring-refinement/mutants.json
```

The temporary contract directory holds a copy of the current Agent obligations
without the historical survivor ledger. The ledger receives a separate exact
site audit. Local evidence stays under
`tmp/covenant/agent-authoring-refinement/`:

| File | SHA-256 |
| --- | --- |
| `catalog.json` | `5319bf7f78a6174e0c12b0faa63e3278ab77401794c068190b4dddbacb3cb6e8` |
| `mutants.json` | `5be49bf2132f79a61c29ab5a702bca8eea97b5ef80cd338812087037d35fd989` |
| `ledger-audit.json` | `41e7992185c6d6461461d6db9b77c4e789723c5a29ee56abf3eafe26a9f88975` |
