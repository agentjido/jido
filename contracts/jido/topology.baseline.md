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

- Root `vsn` options on `use Jido.Topology` currently fail graph validation.
  The guards preserve the default version and do not accept that defect as a
  permanent API promise. Add a positive version guard with the compiler fix.
- Existing Topology documents contain the graph and omit the root Agent.
  A complete combined document needs a separate versioned format decision.
- Runtime activation, AgentServer, Controller, persistence, and dispatch need
  their existing runtime tests. They are outside this authoring component.
- Spark provider declarations remain outside the mutation profiles because of
  the existing asynchronous worker failure documented in `contracts/README.md`.
  Generic mutation operators and this small selection cannot prove all behavior.
  Keep core tests, property tests, and the independent optional authoring corpus.
