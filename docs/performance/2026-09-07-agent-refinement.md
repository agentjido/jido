# Agent refinement before V3 release

## Changes and contract checks

This pass starts at `ca3cebea` on `v3-spike`. It uses the local
`jido_action` V3 `Jido.Flow.Builder`, Registry Deriver, and `Jido.Expr` as
references. The pinned Action dependency already supplies these contracts.
No dependency version changed.

| Area | Decision |
| --- | --- |
| Map and keyword input | Share conversion in `Agent.Authoring.to_attrs/2`. Keep last-value behavior for constructors, instance options, state updates, and caller context. Keep duplicate rejection for authoring. Preserve each boundary's error details and the empty context for `nil`. |
| Route targets and defaults | Share target splitting in Authoring. A tuple with map defaults remains valid, including a struct. The explicit Builder `:defaults` option still requires a plain map. |
| Static field validation | Share name, description, and metadata checks. Keep Builder's existing error messages. State schemas and size limits already use shared checks. |
| Incremental route building | Keep checked routes in reverse order, as Flow Builder does. Check each added route once. Restore declaration order and check the complete definition at build. |
| Registry derivation | Collect entries in one reversed accumulator. Keep sorted map traversal, first-occurrence IDs, and exact deduplication. Remove the unused Codec target wrapper. |
| Emit Directives | Share the three identical validation clauses. Keep explicit Directive schemas and public constructors. |
| Expressions | Use the existing Flow expression boundary. Tests cover equal DSL and runtime `Jido.Expr` expressions, Agent Codec round trips, direct execution, live commits, and failure isolation. Agent metadata and route defaults remain data. |

The Builder change removes repeated checks of earlier routes during append.
It does not cache executable descriptors. Build still checks every route
against its current target. Tests confirm that a target that becomes invalid
after append fails at build, and that reused Builder values retain route order.

The following apparent duplicates have different contracts and remain:

- Authoring modules expose `__agent_config__/0`; behavior modules implement
  `handle_signal/2`; factory modules can return an Agent with a different module.
- Plugin declaration and schema callbacks remain in their existing order.
  They can have visible effects. This pass does not remove their repeated calls.
- Instance Codec validation can run a state transform twice. The existing
  second-parse regression test remains unchanged.
- Registry lookup uses `==`, while map keys use exact equality. A reverse map
  would change lookup for values such as `%URI{port: 1}` and `%URI{port: 1.0}`.
  A regression test preserves both lookup equality and distinct generated IDs.
- Definition caching would need a new freshness contract. Existing tests check
  changed Action schemas after recompilation. No cache was added.

See the prior [contract inspection](cycle-inspection.md) and the rejected
[schema reuse trial](round-22-schema.md) for related checks.

## Benchmark alignment

The shared harness now measures bulk, incremental, and mixed Builder routes,
plus flat and nested Registry derivation and generated encoding. Each case
checks complete returned values. Encoding also checks the decoded definition.
The smoke contract has 158 workloads, up from 144. The scale authoring selection
has 17 workloads: route counts 1, 16, and 64; Registry value counts 1 and 256.

Final authoring measurement:

- Baseline: `b38eb2905a0125c75a1b51def413ca5a7e97af4b`.
- Candidate: `37ee96d6880954b5df1dad9c6ad859c432800630`.
- Elixir 1.20.3, OTP 29, two schedulers, five alternating fresh-VM pairs.
- Scale profile: 10 warm-up calls, 60 timing samples, five resource samples.
- Identical scripts, dependency lock, and runtime settings on both sides.
- The baseline already contains shared validation. This comparison isolates
  the Builder and Deriver changes; it does not measure the complete pass.

Ratios are candidate / baseline. Lower time is better.

| Case | Median time ratio | Lower-time pairs | Sampled process-byte ratio |
| --- | ---: | ---: | ---: |
| Builder, 1 route, incremental | 0.865 | 5/5 | 1.000 |
| Builder, 16 routes, incremental | 0.228 | 5/5 | 0.815 |
| Builder, 64 routes, incremental | 0.060 | 5/5 | 1.000 |
| Builder, 64 routes, mixed | 0.080 | 5/5 | 1.000 |
| Builder, 64 routes, bulk | 0.973 | 3/5 | 1.307 |
| Registry, 256 flat values, derive | 1.015 | 2/5 | 0.927 |
| Registry, 256 nested values, derive | 0.947 | 5/5 | 1.000 |
| Registry, 256 nested values, encode | 1.011 | 0/5 | 1.000 |

Incremental building uses about 77% less median time at 16 routes and 94% less
at 64 routes in this run. It no longer repeats a growing set of route checks.
Bulk timing and Registry timing are close to the baseline, apart from the small
nested-derivation gain. These results do not show a general Codec speed gain.

The 64-route bulk case has a measured memory tradeoff: sampled process memory
is 142,672 bytes versus 109,184 bytes, an increase of 33,488 bytes. Returned
definition sizes are unchanged. The incremental case has the same sampled
process memory on both sides. These are observed barrier samples, not exact
lifetime peaks or allocation totals. Resource runs include setup and cleanup;
timing runs measure only the operation, without tracing.

The first Deriver trial used a MapSet during collection. It increased sampled
memory for several cases, including nested derivation. That extra set was
removed in `a7ef1eca`. The final code uses one list accumulator and the existing
final deduplication pass. Do not use the earlier trial as final evidence.

Raw paired reports and manifests for this local run are under
`/tmp/jido-agent-refinement.zu5xg5/final-authoring`. The earlier trial is under
`/tmp/jido-agent-refinement.zu5xg5/authoring`. These temporary paths are local
evidence, not published artifacts. Reproduce the comparison with the fresh-VM
procedure in the [benchmark guide](../../guides/benchmarks.md). Use the scale
profile and the `authoring/` filter.

Runtime SHA-256, baseline:
`c7653b43b7970073965f8883ce71180ff96766286d77cc938e75cb6effa8011f`.
Runtime SHA-256, candidate:
`02223d498b0eb20b9b58c296913ef2ca84da723d69896aa1ba118088cf86145e`.
Benchmark tool SHA-256:
`5051ca008899c3cccbfb6dc5a1dc38ac16656fa20125f56367463f054d870528`.

## Release test policy

`mix quality` runs core tests and the existing format, compile, lint, and
Dialyzer checks. Its test step runs in a separate test environment:

```sh
mix test test/jido --include flaky --seed 0
```

CI uses this selection. The test helper excludes `:benchmark` and `:example`.
Benchmark tests (`mix benchmarks`) and example tests (`mix examples`) are
secondary and run only when selected separately. Research failures do not block
the core quality check. The 11 known research failures have individual
temporary skip reasons. Their assertions remain unchanged. A metadata-only
audit confirmed 45 research tests, exactly 11 skips, and a reason for every
skip. It did not execute research assertions. The existing DIST-03 core skip
is unchanged. No coverage exclusions or thresholds changed.

See [the test policy](../../guides/testing.md) and
[the research inventory](../../test/examples/99_research/README.md).

## Verification

- `mix quality`: passed, including 980 core tests. The eight excluded tests
  are the seven benchmark tests and the existing DIST-03 skip. Example tests
  are outside the selected paths.
- Unit-only coverage: 93.6%, with 980 passed and eight excluded. No benchmark
  or example assertions contributed to this run. The 90% threshold and the
  coverage configuration are unchanged.
- `mix benchmarks --seed 0`: seven tests passed. The smoke test checks all
  158 benchmark workloads, returned values, term transfers, and cleanup.
- Unit suite on Elixir 1.18.5 / OTP 27: 980 passed, eight excluded. It uses
  the same core selection as quality and a separate build directory.
- Quality failure probe: a simulated failing test command makes quality fail.
  Its child process uses `MIX_ENV=test`; the parent keeps its tool environment.
- `mix docs --no-open -f html --warnings-as-errors`: passed.
- `mix hex.build`: passed. No package was published.
- Before the final suite split, the full core selection passed on both
  Elixir 1.20.3 / OTP 29 and Elixir 1.18.5 / OTP 27: 987 passed, one excluded.
  Coverage was 93.7%. That measurement includes benchmark tests and must not
  be presented as core-only coverage.

The default-runtime tests report existing type warnings in intentional invalid
input tests. The project compilation and strict warning-level lint checks pass.
No example acceptance assertions were run for the final verification.

## Follow-up contract fixes

A later review found three pre-existing errors at Agent boundaries:

- Constructors accepted an unknown `nil` key because `Enum.find/2` also uses
  `nil` when no key is found. Definition and instance checks now inspect the
  list of unknown keys. Tests cover maps, keyword lists, and callback order.
- Codec accepted and encoded struct-valued tuple defaults, then rejected them
  during decode. Decode now restores the tuple form. The explicit authoring
  `:defaults` option remains restricted to plain maps, and invalid non-map
  document defaults retain their error.
- A descriptor failure during Registry derivation raised `MatchError`.
  Route collection now returns the resolver error and stops at the first
  failed route. Tests cover invalid descriptors and raised callback errors at
  the first, middle, and last route. Registry ID order remains unchanged.

The new regression tests produced four failures before these fixes, including
one at each constructor. After the fixes, 101 focused Agent tests pass on
Elixir 1.20.3 / OTP 29 and Elixir 1.18.5 / OTP 27. The separate benchmark
contract suite passes all seven tests. `mix quality` passes with 985 core tests
and eight exclusions. Docs and package checks also pass. No example acceptance
tests ran, and research skips are unchanged.

No paired performance or full coverage run was repeated for these fixes; the
measurements above describe the initial refinement pass.
