# Plugin alignment

## Status

The current source uses owner-facet manifests for bundled Plugins, examples,
and test fixtures. The mixed package callback path and `legacy?` specs are
removed.

## Current evidence

| Source | Evidence |
| --- | --- |
| `lib/jido/agent/plugin/pipeline.ex` | The evaluator `run/5` path protects state, validates each Directive once, and reduces owned state. |
| `lib/jido/agent/plugin.ex` | The Agent facet reads complete state during preparation and returns one portable input. |
| `lib/jido/agent/runner.ex` | The Runner exposes isolated `prepared` and `runtime` slots without changing the source Signal. |
| `lib/jido/agent_server/plugin.ex` | Admission receives a read-only value and returns only its package runtime input. |
| `test/jido/plugin/preparation_test.exs` | Full-state reads, pure input, reduction, direct and live parity, rejection, and portability pass. |
| `test/jido/plugin/contract_test.exs` | Owned-state protection, Directive validation, and reducer isolation pass. |
| `test/jido/plugin/ordering_test.exs` | State reducers run in declaration order and stop at the first error. |
| Core test suite | The package suite checks owner facets, examples, and runtime boundaries. |

## Gap register

| Gap | Owner | State |
| --- | --- | --- |
| Mixed package callback normalization | Plugin declaration | Removed |
| Bundled Plugin migration | Plugin packages | Complete |
| Identity and Secure Signal use package inputs without Signal replacement. | Examples | Fixed |

## Ordered follow-up

1. Keep each new package callback-free with explicit owner facets.
2. Keep custom Directive validation on its Directive module.
3. Run core, example, benchmark, system, docs, and quality checks after each change.

## Acceptance matrix

| Requirement | Evidence |
| --- | --- |
| `PLG-REQ-011` to `PLG-REQ-017` | Agent schema and Plugin contract tests |
| `PLG-REQ-018`, `PLG-REQ-021` to `PLG-REQ-029` | Preparation and admission contract tests |
| `PLG-REQ-031`, `PLG-REQ-032`, `PLG-REQ-035` | Plugin ordering and validation tests |
| `PLG-REQ-036` to `PLG-REQ-039` | Directive ownership and runtime tests |
| `PLG-REQ-040` to `PLG-REQ-051` | Agent Server commit and Plugin lifecycle tests |
| `PLG-REQ-053` to `PLG-REQ-060` | Persistence and Topology facet tests |
