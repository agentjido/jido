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
