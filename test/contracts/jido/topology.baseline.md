# Topology contract baseline

Date: 2026-10-15. Source checkpoint: `e82893a4` on `release/v3`.

This rollout adds guards before Agent and Topology compiler consolidation.
It changes contracts, test support, and tests. Public DSL and implementation
files stay unchanged. The existing 25 Agent obligations remain active; the
Topology component adds 17 obligations and 27 focused tests.

## Verification

| Check | Result |
| --- | --- |
| Format, compile with warnings as errors, warning lint | Passed through `mix quality` |
| Covenant gate | 103 passed; Agent 25/25 and Topology 17/17 obligations covered |
| Core and property tests, seed 0 | 1,531 passed; 51 excluded by the normal core profile |
| Agent and Topology authoring corpus, seed 0 | 444 passed |
| Topology contract tests | 27 passed in each mutation baseline and final original check |
| Topology focused mutation profile | 22 selected; 21 killed; 1 invalid |
| Shared compiler focused profile | 9 selected; 9 killed |

Both mutation jobs completed with no survivors or timeouts. Kills have exact
attribution because the complete Topology contract suite ran for each selected
mutant. The invalid mutation removes an enforced `Topology.Instance.input`
field and cannot compile. It receives no kill credit. No survivor annotations
were required. These results establish no full-component mutation score.

`mix quality` stopped at Dialyzer. A follow-up `MIX_ENV=test mix dialyzer`
reported ten warnings in unchanged files: nine for generated `to_json/0`
functions and unsupported JSON output schemas, and one for the existing Agent
contract's intentional improper-list fixture. The new Topology fixture adds
no Dialyzer warnings. Invalid contribution data is supplied from the test
process so the compiled helper does not construct a known improper list.
No warnings were suppressed. The core tests were run separately because the
quality alias stopped before its test step.

## Focused checks

The Topology profile is the 13-module list in `topology.obligations.md`. The
shared compiler profile overrides that list; shared Agent modules remain owned
by the Agent contract. Spark provider declarations and runtime modules are
outside both mutation selections. Fresh Topology fixtures compile in monitored
processes and wait for compiler exit, including `after_verify`, before use.

The profiles enumerated 1,336 and 265 candidate sites without executing the
excluded sites. Only the selected sites below ran. The earlier 1,302-mutant
Agent profile was not rerun. Run these commands from `jido`:

```sh
MIX_ENV=test mix covenant.mutate jido.topology --macros \
  --only m0018,m0021,m0029,m0032,m0053,m0215,m0239,m0512,m0537,m0607,m0722,m0748,m0766,m0783,m0787,m0823,m0835,m0836,m0852,m0876,m0894,m1142 \
  --jobs 2 --seed 0 --timeout 5000 --max-runtime 240000 \
  --checkpoint --selective-recompile --out tmp/covenant/topology-focused.json

MIX_ENV=test mix covenant.mutate jido.topology \
  --module Jido.Agent.Definition --module Jido.Agent.DSL.Compiler \
  --module Jido.Topology.DSL.Compiler --macros \
  --only m002,m055,m074,m108,m176,m177,m182,m192,m204 \
  --jobs 2 --seed 0 --timeout 5000 --max-runtime 240000 \
  --checkpoint --selective-recompile --out tmp/covenant/topology-host-focused.json
```

Each worker uses a private project copy and must pass its final original suite.
Checkpoints retain only verified groups. Selective compilation changes compile
work, not test selection. There are no precompiled Topology host fixtures to
list with `--recompile`. Re-enumerate sites after implementation or profile
changes; mutant IDs alone are not stable across such changes.

## Selected sites

| Profile | ID | Site | Change | Verdict |
| --- | --- | --- | --- | --- |
| Topology | m0018 | `lib/jido/topology.ex:94:20` | `Jido.Agent.instantiate(__MODULE__, opts) → nil` | killed |
| Topology | m0021 | `lib/jido/topology.ex:107:40` | `Jido.Topology.instantiate(__topology_config__(), opts) → nil` | killed |
| Topology | m0029 | `lib/jido/topology.ex:143:44` | `:input → (removed)` | killed |
| Topology | m0032 | `lib/jido/topology.ex:148:55` | `input: input → (removed)` | invalid |
| Topology | m0053 | `lib/jido/topology/child.ex:16:11` | `if function_exported?(module, :__topology_owner__?, 0) and mod… → if !(function_exported?(module, :__topology_owner__?, 0) and mod…)` | killed |
| Topology | m0215 | `lib/jido/topology/codec.ex:127:10` | `metadata: metadata → (removed)` | killed |
| Topology | m0239 | `lib/jido/topology/codec.ex:169:23` | `== → !=` | killed |
| Topology | m0512 | `lib/jido/topology/composition.ex:101:21` | `== → !=` | killed |
| Topology | m0537 | `lib/jido/topology/composition.ex:159:26` | `== → !=` | killed |
| Topology | m0607 | `lib/jido/topology/composition.ex:320:5` | `if target.kind in allowed → if !(target.kind in allowed)` | killed |
| Topology | m0722 | `lib/jido/topology/plan.ex:51:62` | `== → !=` | killed |
| Topology | m0748 | `lib/jido/topology/plan.ex:127:18` | `== → !=` | killed |
| Topology | m0766 | `lib/jido/topology/plan.ex:149:24` | `== → !=` | killed |
| Topology | m0783 | `lib/jido/topology/plan.ex:182:10` | `id: Composition.escape(id) <> "/" <> key → (removed)` | killed |
| Topology | m0787 | `lib/jido/topology/plan.ex:186:10` | `node: target_node → (removed)` | killed |
| Topology | m0823 | `lib/jido/topology/plan.ex:239:60` | `>= → >` | killed |
| Topology | m0835 | `lib/jido/topology/plan.ex:246:44` | `<= → <` | killed |
| Topology | m0836 | `lib/jido/topology/plan.ex:246:44` | `<= → >` | killed |
| Topology | m0852 | `lib/jido/topology/plan.ex:256:64` | `== → !=` | killed |
| Topology | m0876 | `lib/jido/topology/plugin.ex:85:30` | `or → and` | killed |
| Topology | m0894 | `lib/jido/topology/plugin.ex:144:69` | `error → nil` | killed |
| Topology | m1142 | `lib/jido/topology/validation.ex:257:9` | `reason: reason → (removed)` | killed |
| Shared compiler | m002 | `lib/jido/agent/definition.ex:11:7` | `if constructors? → if !(constructors?)` | killed |
| Shared compiler | m055 | `lib/jido/agent/dsl/compiler.ex:14:7` | `if Module.get_attribute(env.module, :jido_agent_combined_exten… → if !(Module.get_attribute(env.module, :jido_agent_combined_exten…)` | killed |
| Shared compiler | m074 | `lib/jido/agent/dsl/compiler.ex:69:5` | `if Module.get_attribute(env.module, :jido_agent_combined_exten… → if !(Module.get_attribute(env.module, :jido_agent_combined_exten…)` | killed |
| Shared compiler | m108 | `lib/jido/agent/dsl/compiler.ex:113:7` | `schema: Extension.get_opt(dsl, [:agent], :schema, Zoi.object(%{})) → (removed)` | killed |
| Shared compiler | m176 | `lib/jido/topology/dsl/compiler.ex:43:5` | `validate_extensions!(extensions, env) → (removed)` | killed |
| Shared compiler | m177 | `lib/jido/topology/dsl/compiler.ex:41:32` | `:description → (removed)` | killed |
| Shared compiler | m182 | `lib/jido/topology/dsl/compiler.ex:61:14` | `if startup == %{} → if !(startup == %{})` | killed |
| Shared compiler | m192 | `lib/jido/topology/dsl/compiler.ex:85:75` | `== → !=` | killed |
| Shared compiler | m204 | `lib/jido/topology/dsl/compiler.ex:115:5` | `fail!(%{env \| line: line}, Exception.message(error)) → nil` | killed |

## Local evidence

Full matrices and checkpoint groups are local ignored artifacts. Their hashes
identify the exact results used for this record:

| Artifact | SHA-256 |
| --- | --- |
| `tmp/covenant/topology-focused.json` | `f3c7c5dead9406eaaad45db5b8b663b903311268a5d97f95aa6014fd2c1c8455` |
| `tmp/covenant/topology-host-focused.json` | `d0116ad389f74e43877c2d98041851aa7cd11b88a67241c2ee1d91a26f9130f3` |

## Open API decisions

- Root `vsn` options are fixed by the shared compiler change below. A positive
  contract test protects explicit versions and keeps them out of graph fields.
- Existing Topology documents contain the graph and omit the root Agent.
  A complete combined document needs a separate versioned format decision.
- Runtime activation, AgentServer, Controller, persistence, and dispatch need
  their existing runtime tests. They are outside this authoring component.
- Spark provider declarations remain outside the mutation profiles because of
  the existing asynchronous worker failure documented in `test/contracts/README.md`.
  Generic mutation operators and this small selection cannot prove all behavior.
  Keep core tests, property tests, and the independent optional authoring corpus.


## Agent and Topology consolidation

The guard checkpoint is `6900d7d7`. Steps 2–7 keep the public DSL unchanged.
Only the `jido` package changed. AgentServer implementation files did not change.
The unrelated durable-execution design documents are outside this work.

- One internal host selector replaces the paired setup flags. The public
  Agent and Topology entry modules retain their different constructors.
- One final compiler entry reads current options and Spark state. It calls
  separate Agent and graph lowering functions, then verifies both definitions.
  Early Spark checks and deferred caller-scope evaluation remain in place.
- Shared field normalization preserves validation order and Plugin callback
  order. An explicit Agent struct replaces its unused private Zoi schema.
- Each planning call resolves each member Agent source once. It reuses the
  current definition, Plugin specifications, and complete state schema during
  contribution expansion and member creation. Each member still initializes
  and validates its own state. No resolved data survives the planning call.
- `Topology.Source` shares provider loading and fault handling. Static includes
  and runtime children keep their different provider and owner rules.
- Removed unused helpers and duplicate prepared Plugin inputs. Kept the
  internal Pipeline error clause because an existing test protects it.

The implementation adds 294 lines and removes 314 lines under `lib`, including
55 lines in the new source loader: a net reduction of 20 lines.

| Check | Result |
| --- | --- |
| Format, compile with warnings as errors, warning lint | Passed |
| Core and property tests, seed 0 | 1,532 passed; 51 normal profile exclusions |
| Authoring corpus, seed 0 | 444 passed |
| Covenant gate | 108 passed; all 42 obligations covered |
| Shared compiler selection | 13 killed |
| Topology planning selection | 11 killed initially; 2 gaps found and then caught by added tests |
| Shared Agent source selection through Topology | 2 killed |
| Agent selection | 12 killed; 234 existing annotations deferred |

These checks cover 40 distinct selected sites. Every selected site has an exact
kill after the focused follow-up. There are no unresolved selected survivors,
timeouts, or invalid mutants. These results establish no full-component score.
The earlier 1,302-mutant matrix was not rerun. Enumeration of current sites does
not execute those mutants.

The first compiler mutation probe found that compile-time root Agent dependency
verification lacked a direct guard. The final guard rejects invalid root Action
and Plugin contracts. The planning probe found missing guards for module cycles
and improper entry lists. Added tests catch both mutations. The older planning
report retains the two original survivors as evidence; the gap report records
their passing follow-up.

Updated 133 survivor locations. Removed 20 entries for deleted mutation sites.
Replaced three incorrect historical claims with direct tests and focused kills:
`Agent.set/2` can reach its invalid-schema branch, and a later extension route
can reach the non-atom target-option guard. No new survivor exceptions were
added. The remaining 234 annotations were matched to current sites, but the
focused run does not revalidate their historical judgments.

`mix quality` still stops at the same ten existing Dialyzer warnings listed
above. No new warnings or test skips were added. The core tests ran separately.

### Focused artifacts

All mutation runs use seed 0, macro mutation, selective recompilation, a 5,000 ms
per-test timeout, and complete component contract suites. Compiler and final
Agent checks use two workers. The two shared source mutations use one worker.
No fail-fast credit is used. Final compiler and Agent checks omit checkpoints;
input changes during the earlier compiler probe made that checkpoint unusable.

| Artifact | Selected IDs | SHA-256 |
| --- | --- | --- |
| `tmp/covenant/topology-host-refactor.json` | m003, m054, m056, m057, m075, m083, m085, m095, m100, m114, m182, m183, m197 | `3e56e9f4e256e1d887c0e705a51fe03f85f92207dcaaedfbce2553a2e15a1217` |
| `tmp/covenant/topology-planning-refactor.json` | m0733, m0739, m0826, m0832, m0953, m0956, m0965, m0972, m0989, m1038, m1047, m1243, m1246 | `5f11924c981dcb756ebba67f8576a8ea27ee87ef18b88d183cb09b555a8d6ee3` |
| `tmp/covenant/topology-gap-refactor.json` | m0953, m1047 | `468d79f5630ff3cef3d90a1ae255f4c2d20f1fc21118e9f32375975bb65ab4bc` |
| `tmp/covenant/topology-source-refactor.json` | m152, m153 | `78dd50d127347c1f9887f14b3ab1209a6a3b8d5849e18a33da8a56b66f10154d` |
| `tmp/covenant/agent-refactor.json` | m0053, m0059, m0644, m0645, m0646, m0684, m0855, m1177, m1179, m1180, m1181, m1190 | `d227d5bc0070f4eb81c5792818445012f112341e2b7d47fd42c53c0584406852` |

The compiler profile selects `Jido.Agent.Definition`, `Jido.Agent.DSL.Compiler`,
and `Jido.Topology.DSL.Compiler` through the Topology contract. The planning and
gap profiles use the current 14-module Topology list. The shared source profile
selects Agent Source, Validation, Runner, and Extension through that contract.
The final Agent profile uses its normal module list with `--only` for the twelve
listed sites. Re-enumerate IDs when source changes.

## Second Agent and Topology refinement

Only `jido` changed. The public DSL syntax and generated public functions stay
unchanged. This work does not change AgentServer implementation files or the
separate design documents.

### Review and implementation

The review compared the shared `Jido.Authoring` pattern in `jido_action`
without changing that package. Its useful boundary is a shared compiler that
receives lowered values and emits the module API. The jido implementation uses
that boundary without adding a generic framework or a compilation record.

| Area | Change |
| --- | --- |
| Shared compiler | Combine Agent host setup, final compilation, Signal helper generation, and final verification in `Jido.Agent.Authoring.Compiler`. Remove `Agent.Definition`, `Agent.DSL.Compiler`, and `Agent.DSL.Generator`. |
| Topology lowering | Return graph configuration, source locations, and the owner flag. The shared compiler emits both Agent and graph accessors and verifies Agent before Topology. |
| Route options | Use the existing dependency-owned `Jido.Authoring.Options` keyword validator and compile-error helper. |
| Agent construction | Inline the private definition-building wrapper. Keep the keyword adapter, struct handling, and validation order. |
| Extension selection | Load each extension once and check both callback roles in one ordered pass. |
| Route claims | Use the shared proper-list traversal and combine owner lookup with target update. |
| Plugin expansion | Normalize each contribution entry, then check combined names at the same recursive scope. Remove repeated full definition validation. |
| Child planning | Reuse the static composition check done during construction. Check all parent Bus targets before any child planning callback. |
| Topology fields and helpers | Derive accepted collection fields from EntryMetadata. Remove unused validation dispatch and planning helper arities. Calculate Codec version once per encoded definition. |

Library changes add 481 lines and remove 565 lines, including the new compiler:
a net reduction of 84 lines and two modules.

Two added contract tests require an included contribution name conflict to keep
its child-local `[:resources, 1, :key]` path and stop parent callbacks. They also
require every child event target to pass before child contribution callbacks
start. Plugin tests now use public construction and planning functions.

### Boundaries retained

- `Agent.Source.instantiate_with_plugins/3` and
  `Agent.Validation.instantiate_with_plugins/2` have AgentServer consumers.
  An initial caller search missed those consumers; compilation found them,
  and both functions remain unchanged.
- Domain and complete Plugin state schemas enforce separate policies.
  Plugin normalization alone does not enforce the Agent ban on transforms
  and coercion.
- Options evaluate once in the caller module body. Deferred DSL blocks retain
  caller bindings and imports. The early Spark storage check remains before
  final compilation. Agent data is escaped before Topology lowering.
- Agent and Topology extension errors retain their existing source-location
  rules. Shared verification checks the Agent before the graph.
- Graph composition, plans, and runtime instances keep separate purposes.
  Member value references and graph endpoint references keep separate roles.
  A Topology uses an Agent host without putting graph data in Agent state.
- Keep the tested Pipeline error clause. Do not add generic Codec or validation
  layers to remove small domain helpers.

### Verification

The final test and coverage run passed 2,085 tests with 51 normal exclusions.
It includes core, property, Covenant, and optional authoring tests. No new
skips were added. Package line coverage is 92.3%. The current 18-file Agent
mutation profile covers 858/865 relevant lines (99.19%). The 14-file Topology
profile covers 827/853 relevant lines (96.95%). The shared compiler covers
137/138 relevant lines (99.28%).

```sh
MIX_ENV=test mix coveralls.json --preload-modules \
  test/jido test/property test/contract test/authoring \
  --include flaky --include property --include authoring --seed 0 --max-cases 4
```

Format, compilation with warnings as errors, warning-level Credo, and all 42
Covenant obligations pass. `mix quality` stops at the same ten existing
Dialyzer warnings listed above. A new warning from delegating a known error
tuple through the shared unwrap helper was fixed by raising that compile error
directly. No warning suppression was added.

The check used Elixir 1.20.4 and OTP 29.1. The declared Elixir 1.18 and OTP 27
pair was not checked here.

### Focused mutation checks

The first Topology probe found one test gap: dropping the unclaimed-entity
compile error still led to a later compile error, so the existing type-only
assertion passed. The test now requires the authored entity line as well as
its fixture file. This protects the source-location promise without fixing
the diagnostic wording. No survivor exception was added.

The final checks caught all 34 selected mutations: ten through the Agent
component, twelve through the Topology component, and twelve shared compiler
mutations through the Topology contract. There were no selected survivors,
invalid mutants, timeouts, partial verdicts, or new survivor exceptions.

Each run uses macro mode, seed 0, two workers, selective recompilation,
a 5,000 ms test timeout, and the complete component contract suite. No run
uses fail-fast or a checkpoint. The changed compiler profile still belongs
to the Agent component; the Topology check selects it with an explicit override.

| Artifact | Selected IDs | SHA-256 |
| --- | --- | --- |
| `tmp/covenant/agent-host-consolidation.json` | m0183, m0192, m0216, m0348, m0674, m0675, m0677, m0680, m0692, m1121 | `aefdbab3846b275e34cb30c4b3ef6143588acefda68d6144c4a27085731f7e15` |
| `tmp/covenant/topology-host-consolidation.json` | m0125, m0127, m0588, m0589, m0590, m0591, m0605, m0644, m0812, m0813, m1256, m1266 | `8aed525c6d1e07a8ba8bce5be272fcec83d8ebee370abab18e361065d5ddaad9` |
| `tmp/covenant/topology-compiler-host-consolidation.json` | m003, m023, m052, m054, m055, m069, m071, m094, m096, m097, m108, m113 | `801ea336ed91e87d3911685f6b83ae374e2675978b4f010368ef19a0382ad635` |

The first probe remains in
`tmp/covenant/topology-host-consolidation-probe.json`. It had eleven kills and
one survivor before the source-line assertion was added. The final Topology
matrix repeats all twelve selections with that assertion in place.

To reproduce the final focused runs:

```sh
MIX_ENV=test mix covenant.mutate jido.agent --macros \
  --only m0183,m0192,m0216,m0348,m0674,m0675,m0677,m0680,m0692,m1121 \
  --jobs 2 --seed 0 --timeout 5000 --max-runtime 240000 \
  --selective-recompile --out tmp/covenant/agent-host-consolidation.json
MIX_ENV=test mix covenant.mutate jido.topology --macros \
  --only m0125,m0127,m0588,m0589,m0590,m0591,m0605,m0644,m0812,m0813,m1256,m1266 \
  --jobs 2 --seed 0 --timeout 5000 --max-runtime 240000 \
  --selective-recompile --out tmp/covenant/topology-host-consolidation.json
MIX_ENV=test mix covenant.mutate jido.topology \
  --module Jido.Agent.Authoring.Compiler --macros \
  --only m003,m023,m052,m054,m055,m069,m071,m094,m096,m097,m108,m113 \
  --jobs 2 --seed 0 --timeout 5000 --max-runtime 240000 \
  --selective-recompile --out tmp/covenant/topology-compiler-host-consolidation.json
```

IDs depend on the source and module profile. Re-enumerate after source changes.
The current catalog has 1,303 Agent sites, 1,293 Topology sites, and 181 sites
in the single shared compiler profile. Enumeration does not execute mutations.
The earlier complete 1,302-mutant run was not repeated. These checks establish
no full-component mutation score.

The Agent ledger retains 224 exact annotations from the prior full review.
Ten removed sites were retired: eight in the old extension predicate, one
obsolete non-atom fallback, and one in the removed route-option validator.
The current fallback mutation is caught. All retained entries match the
current catalog, including moved compiler sites and qualified error calls.
Their historical judgments remain deferred by the focused run.

## Review fixes F1–F2 — 2026-10-15

F1 now checks static child graphs and command targets recursively during
construction. Invalid descendants fail before parent Plugin contributions.
Parent Bus checks remain in planning. F2 uses one early schema storage check
in the shared authoring compiler. It returns the original schema and lets the
existing semantic checks retain their error paths. Both DSL hosts use it.
The public DSL and AgentServer are unchanged.

Five new contract tests cover child depths one through three, valid Agent and
child command targets, invalid graph and command targets, contribution order,
and all three authored schema roles. Anonymous defaults and refinements have
located DSL errors. Static MFA rules still validate, and escapable invalid
schemas retain their existing `CompileError` locations. The gate now runs 78
Agent tests and 37 Topology tests; all 42 obligations have passing tests.

| Check | Result |
| --- | --- |
| Core and property tests | 1,531 passed; 51 normal exclusions |
| Core line coverage | 92.0%; 90% gate passed |
| Contract tests | 115 passed; 42/42 obligations |
| Optional authoring corpus | 444 passed |
| Format, warning-as-error compilation, warning-level Credo | Passed |
| `mix quality` | Stops at the same ten existing Dialyzer warnings |

The Dialyzer warnings are the nine generated `to_json/0` schema diagnostics
and the intentional improper-list contract fixture. These fixes add no warning.

### Focused mutation evidence

All eight selected checks were killed with exact test attribution: four child
sites and two schema-storage sites, with the latter checked through both Agent
and Topology contracts. There were no selected survivors, timeouts, invalid
mutants, or new survivor exceptions. This is six distinct sites, not a complete
component score. The full 1,302-mutant run was not repeated.

The first child selection found two survivors: removing the child-target case
and swapping its key comparison. A valid child command was added beside the
invalid-target cases. That guard kills both in the final selection.

```sh
MIX_ENV=test mix covenant.mutate jido.topology --macros \
  --only m0113,m0115,m0117,m0119 --jobs 2 --seed 0 --timeout 5000 \
  --max-runtime 240000 --selective-recompile \
  --out tmp/covenant/topology-review-fixes-final.json
MIX_ENV=test mix covenant.mutate jido.agent --macros \
  --only m0349,m0350 --jobs 2 --seed 0 --timeout 5000 \
  --max-runtime 240000 --selective-recompile \
  --out tmp/covenant/agent-review-fixes.json
MIX_ENV=test mix covenant.mutate jido.topology \
  --module Jido.Agent.Authoring.Compiler --macros \
  --only m182,m183 --jobs 2 --seed 0 --timeout 5000 \
  --max-runtime 240000 --selective-recompile \
  --out tmp/covenant/topology-compiler-review-fixes.json
```

Covenant does not generate removal of a `with` qualifier. A separate manual
regression check removed only `validate(child.topology)` from the current
source, ran the depth guard, and restored the exact source bytes in `finally`.
The injected run failed at the invalid grandchild assertion; the restored run
passed. This check is separate from the eight Covenant results. Its report and
both logs are under `tmp/covenant/child-recursion-*`.

| Evidence file | SHA-256 |
| --- | --- |
| `tmp/covenant/topology-review-fixes-final.json` | `08a7ec66c3b2e7d36308f586ee9032f65496036ae13b698800a3758f14f20037` |
| `tmp/covenant/agent-review-fixes.json` | `5c8c5900a09c5c8de228e3683cc72174861f20f111ebfcc8cfa60525241852c5` |
| `tmp/covenant/topology-compiler-review-fixes.json` | `c7a4f25418a655feb3218052ef98b9a2c51acbf32dfa268f21b74d3468433aba` |
| `tmp/covenant/child-recursion-regression.json` | `cedba531449ea1444785737572cecac6228455a1bbb956bac02eb1c4cf11ae57` |

The source catalogs now contain 1,306 Agent sites, 1,293 Topology sites, and
184 shared compiler sites. Catalog enumeration executed no mutations. The
224 prior Agent annotations remain deferred. Spark provider declarations
remain outside mutation profiles; public compilation tests check their wiring.
The declared Elixir 1.18 / OTP 27 floor was not rerun.

## Agent and Topology DRY refinement — 2026-10-15

This pass starts from `e578c829b8c25660f127b48e7165b53710b2ec3d`.
Only `jido` implementation and contract files changed. The public DSL stays
unchanged. AgentServer, dependency packages, and separate design documents
are outside this pass.

### Approved changes

| Area | Change |
| --- | --- |
| Instance document decoding | Agent `decode/3` reuses the validated definition, Plugin specs, and complete schema. Topology `decode/3` passes decoded attributes to construction once. Both paths remove the second definition validation. |
| Nested Codec work | Compound Agent and Plugin Codecs reuse the validated Registry and Plugin specs. Standalone Plugin encoding and decoding keep their full public checks. |
| Scope counts | Seed every composition scope, then count each Agent and resource into its own scope and ancestors. Keep the sorted limit checks before member state validation. Empty scopes remain in the result. |
| Root options | Split root options once in the shared compiler. Keep `:name` in both roots. Agent `:description` and `:vsn` stay in the Agent definition. The Agent host still rejects unknown root keys. |
| Graph metadata | EntryMetadata owns each kind's canonical collection. DSL Entity retains the authored section and entity module. The compiler derives the collection from that shared metadata. |

Agent Codec operations reuse the current Plugin specs. Topology instance
decoding resolves source contracts once. The next operation reads them again.
The checks retain document bounds,
standalone Plugin validation, structured errors, and error order. Static child
validation still stops invalid descendants before parent contributions. The
scope accumulator retains the exact component map and nested limit behavior.

Contract guards cover current Plugin reads, nested Codec errors and Registry
kinds, root option roles, collection mapping, exact nested and sibling counts,
empty scopes, and limit failure before invalid member state.

### Verification

| Check | Result |
| --- | --- |
| Contract tests | 122 passed: 80 Agent and 42 Topology; all 42 obligations have passing tests |
| Core and property tests | 1,531 passed; 51 normal exclusions |
| Core test line coverage | 91.9%; the 90% gate passed |
| Optional authoring corpus | 444 passed on the final production source |
| Format, compile with warnings as errors, warning lint | Passed |
| Final combined tests and coverage | 2,097 passed; 51 normal exclusions; 92.4% package line coverage |
| Dialyzer | The same ten existing warnings; no new warnings or suppressions |
| Declared Elixir 1.18 / OTP 27 floor | Not run in this pass |

No new skips were added. The combined run includes core, property, contract,
and optional authoring tests. It passes the package's 90% coverage gate.

| Changed module | Line coverage |
| --- | --- |
| `Jido.Agent` | 97.9% |
| `Jido.Agent.Authoring.Compiler` | 99.2% |
| `Jido.Agent.Codec` | 100.0% |
| `Jido.Agent.Validation` | 99.1% |
| `Jido.Plugin.Codec` | 100.0% |
| `Jido.Topology.Codec` | 91.1% |
| `Jido.Topology.DSL.Compiler` | 100.0% |
| `Jido.Topology.DSL.Entity` | 73.6% |
| `Jido.Topology.EntryMetadata` | 100.0% |
| `Jido.Topology.Plan` | 97.1% |

The completed core and authoring commands were:

```sh
MIX_ENV=test mix covenant.check
MIX_ENV=test mix test test/jido test/property \
  --include flaky --include property --seed 0 --cover
MIX_ENV=test mix test.authoring
```

The final combined coverage command is:

```sh
MIX_ENV=test mix coveralls.json --preload-modules \
  test/jido test/property test/contract test/authoring \
  --include flaky --include property --include authoring --seed 0 --max-cases 4
```

Quality tasks ran separately. Dialyzer returned exit code 2 for the same ten
existing warnings: nine generated JSON schema diagnostics and the intentional
improper-list fixture. No changed production code has a new warning.

```sh
MIX_ENV=test mix format --check-formatted
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix credo --strict --only warning
MIX_ENV=test mix dialyzer
```

| Verification evidence | SHA-256 |
| --- | --- |
| `cover/cov.json` | `cd8070e4c5709a828a4d73727207c9a2d942e73bc12898f73be618f28f3dd9bb` |
| `tmp/covenant/dry-refinements-coverage.log` | `2442eef48272529b4b67696961dab9a45ebb3068fc718b08d9df954e55975ff3` |
| `tmp/covenant/dry-refinements-contract-check.log` | `bea33344c3f15376e61a09534d3892a38b4d2f6ad73b90f587542d24e210ffd4` |
| `tmp/covenant/dry-refinements-dialyzer.log` | `3438bb7cbb1aeca1e4fc7f0aebf38838ae2484199f7ceac839ef19fe708cf911` |

### Focused mutation evidence

The completed final selections killed all 19 distinct sites: nine Agent sites,
nine Topology sites, and one shared compiler site through the Topology
contract. These selections have exact test attribution and no survivors,
invalid mutants, timeouts, or partial verdicts.

The first six-site Agent probe killed five and left `m0245` alive. Without
the Agent root-key check, a later DSL error still satisfied the existing
invalid-DSL assertion. That test now supplies overlapping root
`:schema`, `:metadata`, `:routes`, and `:plugins` options. It requires the
early root-key rejection. The final six-site run kills `m0245`. This extends
an existing test and does not change the 80-test Agent count.

| Profile | ID | Exact site | Injected change | Result |
| --- | --- | --- | --- | --- |
| Agent | `m0245` | `lib/jido/agent/authoring/compiler.ex:258:5` | Remove the Agent root-key check in `split_options/3` | Killed in final run |
| Agent | `m0436` | `lib/jido/agent/codec.ex:58:5` | Return nil from `encode_validated/2` | Killed |
| Agent | `m0478` | `lib/jido/agent/codec.ex:116:5` | Return nil from `decode/3` | Killed |
| Agent | `m1197` | `lib/jido/agent/validation.ex:186:43` | Remove the Plugin Spec clause in `plugins_at/2` | Killed |
| Agent | `m1315` | `lib/jido/plugin/codec.ex:34:5` | Return nil from `encode_declaration/2` | Killed |
| Agent | `m1328` | `lib/jido/plugin/codec.ex:63:5` | Return nil from `decode_spec/2` | Killed |
| Topology | `m0188` | `lib/jido/topology/codec.ex:131:10` | Remove the decoded schema field | Killed |
| Topology | `m0192` | `lib/jido/topology/codec.ex:142:5` | Return nil from `decode/3` | Killed |
| Topology | `m0650` | `lib/jido/topology/dsl/entity.ex:8:5` | Remove the group entity mapping | Killed |
| Topology | `m0654` | `lib/jido/topology/dsl/entity.ex:12:5` | Remove the include entity mapping | Killed |
| Topology | `m0841` | `lib/jido/topology/entry_metadata.ex:78:70` | Select tuple element 1 instead of 0 in `collection/1` | Killed |
| Topology | `m0889` | `lib/jido/topology/plan.ex:106:67` | Remove the zero Agent count seed | Killed |
| Topology | `m0896` | `lib/jido/topology/plan.ex:114:15` | Remove the limit-error clause | Killed |
| Topology | `m0902` | `lib/jido/topology/plan.ex:120:62` | Change the count increment from 1 to 0 | Killed |
| Topology | `m0905` | `lib/jido/topology/plan.ex:124:58` | Drop two path parts instead of one during ancestor counting | Killed |
| Shared compiler through Topology | `m076` | `lib/jido/agent/authoring/compiler.ex:254:50` | Remove `:name` from `Map.take/2` | Killed |
| Agent | `m0169` | `lib/jido/agent/authoring/compiler.ex:8:31` | Remove `:description` from the shared root-option list | Killed |
| Agent | `m0170` | `lib/jido/agent/authoring/compiler.ex:8:45` | Remove `:vsn` from the shared root-option list | Killed |
| Agent | `m0341` | `lib/jido/agent/authoring/compiler.ex:393:42` | Return nil instead of raising the error in `unwrap!/2` | Killed |

All completed runs use macro mutation, seed 0, a 5,000 ms test timeout,
selective recompilation, and the complete component contract suite. Agent and
Topology runs use two workers and a 240,000 ms runtime limit. The shared
compiler run uses one worker and a 120,000 ms runtime limit. No run uses a
checkpoint or fail-fast credit.

```sh
MIX_ENV=test mix covenant.mutate jido.agent --macros \
  --only m0245,m0436,m0478,m1197,m1315,m1328 \
  --jobs 2 --seed 0 --timeout 5000 --max-runtime 240000 \
  --selective-recompile --out tmp/covenant/agent-dry-refinements-final.json
MIX_ENV=test mix covenant.mutate jido.topology --macros \
  --only m0188,m0192,m0650,m0654,m0841,m0889,m0896,m0902,m0905 \
  --jobs 2 --seed 0 --timeout 5000 --max-runtime 240000 \
  --selective-recompile --out tmp/covenant/topology-dry-refinements.json
MIX_ENV=test mix covenant.mutate jido.topology \
  --module Jido.Agent.Authoring.Compiler --macros --only m076 \
  --jobs 1 --seed 0 --timeout 5000 --max-runtime 120000 \
  --selective-recompile --out tmp/covenant/topology-compiler-dry-refinements.json
```

The three compiler sites use this additional focused selection:

```sh
MIX_ENV=test mix covenant.mutate jido.agent --macros --only m0169,m0170,m0341 \
  --jobs 2 --seed 0 --timeout 5000 --max-runtime 240000 \
  --selective-recompile --out tmp/covenant/agent-root-options-dry-refinements.json
```

| Evidence file | SHA-256 |
| --- | --- |
| `tmp/covenant/agent-dry-refinements.json` — first probe | `8ad80a60831a6942f1e9825fdb7bd4041c7402718851f5d7afa11aa622b0fc3c` |
| `tmp/covenant/agent-dry-refinements-final.json` | `88abd18fed77dbaf5f87d3f8c3f6494d382069c6c2843fc490e6b52b0145ba8e` |
| `tmp/covenant/topology-dry-refinements.json` | `78a0a6f78e5bef7eb61813a0ffbda0c27fe2151bef6dcbce2d35ea4d27dc6cbe` |
| `tmp/covenant/topology-compiler-dry-refinements.json` | `5e84aa6ef22e09fd54778758d51db331a007f0d5428ccf2280815f409418a028` |
| `tmp/covenant/agent-root-options-dry-refinements.json` | `8852298cb3164bf10291d152ce1e1685bf2546b54a788eb3956b2d0b9022812f` |

### Catalog and annotation limits

The current catalogs contain 1,345 Agent sites, 1,512 Topology sites, and
182 shared compiler sites. These are enumerated candidates, not executed
mutations. Catalog enumeration used:

```sh
MIX_ENV=test mix run --no-start --no-compile --no-deps-check \
  tmp/covenant/dry-refinements-catalog.exs
```

The Agent ledger retains 220 historical annotations. Of these, 53 locations
moved, and all 220 match exact sites in the current Agent catalog. Four old
decisions were retired. One old `:name` site was replaced by the `Map.take/2`
site checked as `m076`. The old decisions for `:description` and `:vsn` cannot
apply to the new shared root-option list: removing either key now rejects valid
Agent roots. The old `unwrap!/2` error-branch decision also no longer applies.
The three extra compiler selections check those changed contracts. No new
survivor exceptions are accepted by this pass.

The earlier full 1,302-mutant run was not repeated. Focused checks do not
revalidate the retained historical judgments or establish a current full
component mutation score.

### Separate manual regression probes

Two manual probes restore the old Agent and Topology `Codec.decode/3` bodies
separately. Each runs its focused once-per-operation contract test, restores
the exact original source bytes in `finally`, and records SHA-256 restore
proof. Both original tests then run after restoration. These two semantic
probes are separate from the 19 completed Covenant sites. They receive no
Covenant kill credit.

```sh
python3 tmp/covenant/dry-refinements-regressions.py
```

Each of these commands ran once with the old body and once after restoration:

```sh
MIX_ENV=test mix test test/contract/jido/agent_codec_contract_test.exs:24 --seed 0
MIX_ENV=test mix test test/contract/jido/topology_document_contract_test.exs:83 --seed 0
```

Both old bodies failed the new duplicate-callback guard with exit code 2.
Both restored tests passed with exit code 0. Each source file was restored
byte for byte, with matching before and after SHA-256 digests. The report is
`tmp/covenant/dry-refinements-regressions-20261016T003000Z-27884/report.json`;
its SHA-256 is
`6102d70ec823b9caab61b15aeb6747dc58bd29e1eaf6faa88a694153a10219ee`.
The four phase logs and both original source snapshots are beside the report.

## Code reduction — 2026-10-15

This pass builds on the uncommitted DRY refinements above. Only `jido`
changed. The public DSL stays unchanged. AgentServer, dependency packages,
and the separate design documents stay unchanged.

### Changes and guards

- Build the seven entity sections from one explicit list. Keep startup separate.
  Lower nonempty entity collections directly and remove two small compiler
  helpers. Mark an explicit Agent block directly, without the registration wrapper.
- Return one normalized `%Jido.Topology{}` from validation. Remove the include
  and child conversions and the final container parse. Supplied structs still
  pass all field, graph, and child checks.
- Share map-pair decoding in `Jido.Codec.Data.decode_map/3`. Keep recursive
  Topology reference decoding, caller guards, and each domain's error messages.
- Validate owners before subscriptions, then apply both indexes to each node
  in one pass. Preserve ownership policy, subscription order, and stable
  dependency order.
- Remove the two unused include-normalization clauses. Includes still use
  their ancestor-aware validation path.

Relative to the source at the start of this pass, `lib/` has **60 added lines
and 128 removed lines: net -68** across ten files. The complete uncommitted
library diff, including the prior pass, is 156 added and 185 removed: net -29.
The saved starting hashes and source copies are under
`tmp/covenant/collapse-refinements/`.

The contract gate now has 125 tests: 81 Agent and 44 Topology. Three new tests
cover canonical nested definitions and supplied-struct validation, and nested
map-key collisions after trusted Registry alias resolution. Extended guards
cover exact dependencies, ownership and subscription error order, all core
collections, empty blocks, nested graph references, and nondefault startup
values declared in a block. Core Codec tests retain malformed-map messages
and proper-list errors.

### Verification

| Check | Result |
| --- | --- |
| Combined core, property, contract, and authoring suite | 2,100 passed; 51 normal exclusions |
| Combined package line coverage | 92.4%; 90% gate passed |
| Final Covenant gate | 125 passed; all 42 obligations have passing tests |
| Forced compile with warnings as errors | Passed |
| Final format, compile, and warning lint | Passed |
| Dialyzer | Same ten existing warnings, at the same locations and with the same kinds; no new warnings or suppressions |
| Declared Elixir 1.18 / OTP 27 floor | Not run in this pass |

No skips were added. The combined suite ran on the final production source
before the last startup assertion was added. The final contract gate and the
final seven-site Topology mutation run include that assertion. The final
production bytes match those used in the combined suite.

```sh
MIX_ENV=test mix coveralls.json --preload-modules \
  test/jido test/property test/contract test/authoring \
  --include flaky --include property --include authoring --seed 0 --max-cases 4
MIX_ENV=test mix compile --force --warnings-as-errors
MIX_ENV=test mix format --check-formatted
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix credo --strict --only warning
MIX_ENV=test mix covenant.check
MIX_ENV=test mix dialyzer
```

### Focused Covenant mutations

The final selections kill all 12 component checks at ten distinct source sites.
The two shared map-decoder sites run through both component contracts. Every
selected result has exact attribution, with no invalid mutants, survivors,
timeouts, or partial credit. Each mutant runs its complete component contract
suite: 81 Agent tests or 44 Topology tests.

The first seven-site Topology probe killed six sites and left `m0590` alive.
The contract suite did not check startup values declared in a block. The
core-section test now declares and checks all four nondefault startup values.
The final seven-site run kills `m0590`. This adds assertions, not a survivor
exception, and keeps the 44-test Topology count.

| Profile | ID | Exact site | Operator | Final result |
| --- | --- | --- | --- | --- |
| Topology | `m0389` | `lib/jido/topology/codec/value.ex:50:10` | `return_nil` | Killed |
| Topology | `m0502` | `lib/jido/topology/composition.ex:156:63` | `element_removal` | Killed |
| Topology | `m0511` | `lib/jido/topology/composition.ex:178:57` | `element_removal` | Killed |
| Topology | `m0512` | `lib/jido/topology/composition.ex:180:7` | `condition_negate` | Killed |
| Topology | `m0519` | `lib/jido/topology/composition.ex:191:5` | `return_nil` | Killed |
| Topology | `m0590` | `lib/jido/topology/dsl/compiler.ex:54:37` | `element_removal` | Killed |
| Topology | `m0602` | `lib/jido/topology/dsl/compiler.ex:81:78` | `boolean_flip` | Killed |
| Shared Data through Agent | `m1432` | `lib/jido/codec/data.ex:106:27` | `clause_removal` | Killed |
| Shared Data through Agent | `m1433` | `lib/jido/codec/data.ex:111:16` | `clause_removal` | Killed |
| Shared Data through Agent | `m1438` | `lib/jido/codec/data.ex:118:7` | `boolean_flip` | Killed |
| Shared Data through Topology | `m126` | `lib/jido/codec/data.ex:106:27` | `clause_removal` | Killed |
| Shared Data through Topology | `m132` | `lib/jido/codec/data.ex:118:7` | `boolean_flip` | Killed |

The commands below match the saved source and catalogs. Enumeration does not
execute mutations. The Agent check keeps its declared modules and adds shared
Data through explicit overrides; the permanent ownership list stays unchanged.
All runs use seed 0, a 5,000 ms per-test timeout, selective recompilation,
and no fail-fast or checkpoint credit.

```sh
MIX_ENV=test mix covenant.mutate jido.topology --macros \
  --only m0389,m0502,m0511,m0512,m0519,m0590,m0602 \
  --jobs 2 \
  --seed 0 \
  --timeout 5000 \
  --max-runtime 240000 \
  --selective-recompile \
  --out tmp/covenant/collapse-refinements/topology-mutants-final.json

MIX_ENV=test mix covenant.mutate jido.agent --macros \
  --module Jido.Agent \
  --module Jido.Agent.Authoring.Compiler \
  --module Jido.Agent.DSL.Macros \
  --module Jido.Agent.Authoring \
  --module Jido.Agent.Authoring.Extension \
  --module Jido.Agent.Authoring.SourceMap \
  --module Jido.Agent.Extension \
  --module Jido.Agent.Source \
  --module Jido.Agent.Validation \
  --module Jido.Agent.State \
  --module Jido.Agent.Codec \
  --module Jido.Agent.Codec.Deriver \
  --module Jido.Plugin.Codec \
  --module Jido.Agent.Runner \
  --module Jido.Agent.Turn \
  --module Jido.Agent.Plugin \
  --module Jido.Agent.Plugin.Pipeline \
  --module Jido.Agent.Interface \
  --module Jido.Agent.Callback \
  --module Jido.Codec.Data \
  --only m1432,m1433,m1438 \
  --jobs 2 \
  --seed 0 \
  --timeout 5000 \
  --max-runtime 240000 \
  --selective-recompile \
  --out tmp/covenant/collapse-refinements/data-agent-mutants.json

MIX_ENV=test mix covenant.mutate jido.topology --macros \
  --module Jido.Codec.Data \
  --only m126,m132 \
  --jobs 1 \
  --seed 0 \
  --timeout 5000 \
  --max-runtime 240000 \
  --selective-recompile \
  --out tmp/covenant/collapse-refinements/data-topology-mutants.json

```

The initial and final Topology reports remain separate. No full component
mutation score is claimed. The earlier full 1,302-mutant run was not repeated.

The Agent ledger retains 219 historical entries. Eight entries moved by four
lines. The entry for the removed Agent-block registration wrapper was retired.
All retained entries match exact current catalog sites. Their judgments were
not changed, and no new survivor exceptions were added. Focused runs defer
these historical entries; they do not revalidate their verdicts.

### Separate semantic probes

Six manual probes check defects that generic operators do not directly express:
returning a plain definition map, trusting a supplied struct, moving the parent
after authored dependencies, omitting subscription dependencies, checking
subscriptions before owners, and decoding nested graph references with the
ordinary data decoder. All six fail their selected public contract guard.
These probes receive no Covenant kill credit.

Each probe restores the exact source bytes in `finally`. All three source
files have equal before and after SHA-256 hashes. All four selected original
tests pass after restoration. The final contract gate runs after these probes.

```sh
python3 tmp/covenant/collapse-refinements/manual-regressions.py
```

| Evidence | SHA-256 |
| --- | --- |
| `cover/cov.json` | `1a9c88beba3dc1e04ef48fccbca44e2746969a8442756665505ea866ef0e1c97` |
| `tmp/covenant/collapse-refinements/coverage.log` | `17844e93a8691805ae516ca6bb77c1c09faca2fa846718d4c9f27908fb1397cf` |
| `tmp/covenant/collapse-refinements/contracts-final.log` | `dee4ee0bdb9d925f15f3e1f8355fdf8a1ef1b76a7adbb013f925dc6232e219fa` |
| `tmp/covenant/collapse-refinements/topology-mutants.json` | `147fc6384ebeacc86553c6f7688b3a527d3abf11c8bbee691e799df7b8f3e10a` |
| `tmp/covenant/collapse-refinements/topology-mutants-final.json` | `78f8ea439f5f4db1e91988099a6537c6c00d788dbccf81225e36ac3ebe1b243d` |
| `tmp/covenant/collapse-refinements/data-agent-mutants.json` | `0ab06113e763ff995f48a6d0dbe9b88cb54ef5559d457779ab8d6b6574482f44` |
| `tmp/covenant/collapse-refinements/data-topology-mutants.json` | `ed57405478bdac196fbd6bd31046abf9c36417a92af5a700a0813fff8f0c8f19` |
| `tmp/covenant/collapse-refinements/manual/report.json` | `1c0d1bea3c0024b8c39a6b39c2f7e4951bdf18e19e7c754c6f8f438aca1d3999` |
| `tmp/covenant/collapse-refinements/dialyzer.log` | `8f769901f309df38e9ee333436025024558d0e3e32279e9882851f27693194ad` |
| `tmp/covenant/collapse-refinements/dialyzer-comparison.json` | `778859b718240173e3630a35ed543d0ca8bb1ca41a84b47a993e4a9f894d7a1a` |

## Remaining authoring reductions — 2026-10-15

This pass completes items 1–15. It uses one Agent default source, one
validation-only loop, one indexed/plain list walker, one bang-result unwrap,
and one loaded Agent-module predicate. Codec collectors now live in their
Codecs; both internal Deriver modules are removed. Topology planning checks
member state with `State.initialize/2` and does not build a temporary Agent.
Counted groups are built directly, and scopes receive bindings at creation.
The source helper delegates to Agent Source. The unused `Plan.build/3` wrapper
and one-use schema helper are removed. Route macro defaults, schema defaults,
proper-list checks, and validation errors use the shared paths.

Against the saved source from the start of this pass, `lib/` has 202 added and
345 removed lines: **143 fewer lines**. Only Jido changed. The public DSL,
AgentServer source, and the other thread's design documents are unchanged.
A byte-hash audit checks all 145 protected files from that snapshot.

The core, property, authoring, and contract suite passes **2,104 tests**, with
51 existing tag exclusions and **92.4%** package line coverage. The final
Covenant gate passes **129 tests**: 84 Agent and 45 Topology. All 42 obligations
pass. New checks cover omitted versus explicit nil defaults, shared Agent
module acceptance, route arities, bang error propagation, improper route
lists, and member initialization with defaults and immutable refinements.
Ten authoring benchmark workloads also pass their result checks.

Format, forced compilation with warnings as errors, and warning lint pass.
Dialyzer retains exactly the same ten existing findings; no warning is
suppressed. The local runtime remains Elixir 1.20.4 / OTP 29.1. The declared
Elixir 1.18 / OTP 27 floor was not checked.

```sh
MIX_ENV=test mix coveralls.json --preload-modules \
  test/jido test/property test/contract test/authoring \
  --include flaky --include property --include authoring --seed 0 --max-cases 4
MIX_ENV=test mix format --check-formatted
MIX_ENV=test mix compile --force --warnings-as-errors
MIX_ENV=test mix credo --strict --only warning
MIX_ENV=test mix covenant.check
MIX_ENV=test mix dialyzer
```

### Focused mutation result

All **19 selected mutants are killed**, with exact attribution, complete
component contract runs, no invalid mutants, no survivors, no partial credit,
and no timeouts. The registry-agent profile adds `Jido.Codec.Registry` to the
current Agent module list through explicit overrides; the ownership list is
unchanged. Its shared predicate mutation is tested through both Agent and
Registry public calls. Enumeration does not execute mutations. The earlier
full 1,302-mutant run was not repeated; no full-profile score is claimed.

| Profile | ID | Site | Operator | Change |
| --- | --- | --- | --- | --- |
| agent | m0136 | `lib/jido/agent/authoring.ex:94:52` | integer_shift | `1` → `0` |
| agent | m0137 | `lib/jido/agent/authoring.ex:99:49` | return_nil | `error("Expected a proper list")` → `nil` |
| agent | m0140 | `lib/jido/agent/authoring.ex:104:13` | clause_removal | `case :ok ->` → `(removed)` |
| agent | m0141 | `lib/jido/agent/authoring.ex:105:29` | clause_removal | `case {:error, _} = error ->` → `(removed)` |
| agent | m0147 | `lib/jido/agent/authoring.ex:119:37` | return_nil | `raise(error)` → `nil` |
| agent | m0501 | `lib/jido/agent/codec.ex:161:30` | element_removal | `{:route_match, route.match}` → `(removed)` |
| agent | m0952 | `lib/jido/agent/state.ex:12:18` | comparison_swap | `!=` → `==` |
| agent | m1148 | `lib/jido/agent/validation.ex:120:35` | element_removal | `module: Agent` → `(removed)` |
| agent | m1149 | `lib/jido/agent/validation.ex:120:50` | element_removal | `schema: Zoi.object(%{})` → `(removed)` |
| topology | m0121 | `lib/jido/topology/child.ex:126:29` | element_removal | `to: nil` → `(removed)` |
| topology | m0186 | `lib/jido/topology/codec.ex:129:9` | element_removal | `{:schema, definition.schema}` → `(removed)` |
| topology | m0191 | `lib/jido/topology/codec.ex:137:54` | element_removal | `{:agent, module}` → `(removed)` |
| topology | m0193 | `lib/jido/topology/codec.ex:139:56` | return_nil | `Jido.Agent.Codec.registry_entries(definition)` → `nil` |
| topology | m0457 | `lib/jido/topology/composition.ex:57:7` | element_removal | `bindings: bindings` → `(removed)` |
| topology | m0890 | `lib/jido/topology/plan.ex:124:17` | condition_negate | `if count == 0` → `if !(count == 0)` |
| topology | m0894 | `lib/jido/topology/plan.ex:124:46` | integer_shift | `1` → `2` |
| topology | m0896 | `lib/jido/topology/plan.ex:126:77` | element_removal | `index: &1` → `(removed)` |
| topology | m0927 | `lib/jido/topology/plan.ex:179:10` | element_removal | `module: definition.module` → `(removed)` |
| registry-agent | m1260 | `lib/jido/agent/validation.ex:283:92` | logical_swap | `or` → `and` |

The commands use seed 0, a 5,000 ms per-test timeout, selective recompilation,
and no fail-fast or checkpoint credit. IDs apply to this source and profile.

```sh
env MIX_ENV=test mix covenant.mutate jido.agent --macros \
  --only m0136,m0137,m0140,m0141,m0147,m0501,m0952,m1148,m1149 \
  --jobs 2 --seed 0 --timeout 5000 --max-runtime 240000 --selective-recompile \
  --out tmp/covenant/remaining-refinements/agent-mutants.json

env MIX_ENV=test mix covenant.mutate jido.topology --macros \
  --only m0121,m0186,m0191,m0193,m0457,m0890,m0894,m0896,m0927 \
  --jobs 2 --seed 0 --timeout 5000 --max-runtime 240000 --selective-recompile \
  --out tmp/covenant/remaining-refinements/topology-mutants.json

env MIX_ENV=test mix covenant.mutate jido.agent --macros \
  --module Jido.Agent \
  --module Jido.Agent.Authoring.Compiler \
  --module Jido.Agent.DSL.Macros \
  --module Jido.Agent.Authoring \
  --module Jido.Agent.Authoring.Extension \
  --module Jido.Agent.Authoring.SourceMap \
  --module Jido.Agent.Extension \
  --module Jido.Agent.Source \
  --module Jido.Agent.Validation \
  --module Jido.Agent.State \
  --module Jido.Agent.Codec \
  --module Jido.Plugin.Codec \
  --module Jido.Agent.Runner \
  --module Jido.Agent.Turn \
  --module Jido.Agent.Plugin \
  --module Jido.Agent.Plugin.Pipeline \
  --module Jido.Agent.Interface \
  --module Jido.Agent.Callback \
  --module Jido.Codec.Registry \
  --only m1260 \
  --jobs 1 --seed 0 --timeout 5000 --max-runtime 240000 --selective-recompile \
  --out tmp/covenant/remaining-refinements/registry-agent-mutants.json

```

A separate semantic probe bypasses the member initialization with-clause.
The new member-state guard fails on that defect. The probe keeps all variables
and aliases used, restores the exact source bytes in `finally`, and then
passes the original test. The final Covenant gate runs after restoration.
This manual probe receives no Covenant kill credit.

The Agent ledger retains 215 historical decisions: 104 unchanged and 111
moved or descriptor-adjusted. Four old sites are retired: two removed
constructor fields and two fallback judgments whose old dead-code reason no
longer applies to the merged indexed route walker. Every retained decision
matches an exact current catalog site. No judgment or new survivor exemption
was added. Focused runs defer these historical verdicts.

Local evidence remains ignored. These digests identify the reports and scripts:

| Evidence | SHA-256 |
| --- | --- |
| `tmp/covenant/remaining-refinements/coverage.log` | `264d04daa428e5e4a500bcfaaffb5a831faa87e5fa05af80371da12791d666c6` |
| `tmp/covenant/remaining-refinements/contracts-restored.log` | `465eab0319907a6cc4aa6a2010d068629208e92dbdf14b9bc289f750c3536bd1` |
| `tmp/covenant/remaining-refinements/agent-mutants.json` | `e27aa36edd61198744e78710bbbc679f9953856c6966bbc7977c7d6014e8d57a` |
| `tmp/covenant/remaining-refinements/topology-mutants.json` | `6e3dd9be963d63831039b0fc63097e5e6ea0f5b9c4275dfcaad6f95d03ef3aef` |
| `tmp/covenant/remaining-refinements/registry-agent-mutants.json` | `8aa408f57ed5517eb6a7c8be6e8d25ede7e97c54c627877d78cd54a4cf547e9e` |
| `tmp/covenant/remaining-refinements/mutation-commands.json` | `f9325f0447a13c553ba9c239b59a1b92459209f23b06ab59395470dab1455175` |
| `tmp/covenant/remaining-refinements/manual/report.json` | `ea9d0f0884e6d2245f3d12d352cc72cc7c494d9769014b667c81dd55a48c64e9` |
| `tmp/covenant/remaining-refinements/agent-ledger-rebase.json` | `70955f85c9ef1c0c84344864407af5ef6e38e3301f205d76f590bc27f78e1bb9` |
| `tmp/covenant/remaining-refinements/dialyzer-comparison.json` | `778859b718240173e3630a35ed543d0ca8bb1ca41a84b47a993e4a9f894d7a1a` |
| `tmp/covenant/remaining-refinements/scope-audit.json` | `d5bc16c96bf0fba89d90b2915a1bed1e2c14a13f06d80ad917d0d15e0b7c173e` |
| `tmp/covenant/remaining-refinements/quality-results.json` | `ab85f83f261afd3c645282c49cb7a436d7e5c51ff3c574504311ebbf8183a74d` |
| `tmp/covenant/remaining-refinements/closeout-results.json` | `136d67eb1cbba64ba1706abf751569096eabcbebfc71a4acad9d5055128a138d` |
| `tmp/covenant/remaining-refinements/final-lib-hashes.json` | `d4b65a897b5cab3d312a13474048e215bae710cf898798f9a4076e6f5d7b3be7` |
| `tmp/covenant/remaining-refinements/run-mutants.py` | `e29522a17c632aa7bb5a77c8df8d6d07f58df53a2336a398abecdc51f9e8ddf0` |
| `tmp/covenant/remaining-refinements/manual-regressions.py` | `9df577f5cfa3609ebe86374ecbff9dc2cdf2ff0af952e452a92c5ee851bfa47e` |
| `cover/cov.json` | `2838c400b173d59240a66668b4cf582f2324e088a1574325981e6edf1d21292a` |
