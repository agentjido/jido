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
