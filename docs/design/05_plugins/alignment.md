# Plugin alignment

## Status

The one-phase Agent Plugin pipeline is implemented on branch `v3-spike`.
The complete package cleanup is not complete.

## Current evidence

| Source | Evidence |
| --- | --- |
| `lib/jido/agent/plugin/pipeline.ex` | One `run/3` entry point protects state, validates Directives, and updates owned state. |
| `lib/jido/agent/plugin.ex` | The Agent facet has state, Directive, validation, and update callbacks only. |
| `lib/jido/agent/runner.ex` | The Runner has no Agent Plugin preparation or Plugin input map. |
| `test/jido/plugin/contract_test.exs` | Owned-state protection, Directive validation, and reducer isolation pass. |
| `test/jido/plugin/ordering_test.exs` | State updates run in declaration order and stop at the first error. |
| Core test suite | 1,017 tests passed with example, benchmark, peer, flaky, and skipped tags excluded. |

## Gap register

| Gap | Owner | State |
| --- | --- | --- |
| Mixed `use Jido.Plugin` package callbacks remain in the normalizer. | Plugin declaration | Open |
| Built-in Plugins still use the mixed package form. | Plugin packages | Open |
| Example-only support code used Agent Plugin preparation. | Examples | Fixed |
| Dependent seam documents can still contain old preparation terms. | Design documentation | Open |

## Ordered follow-up

1. Move each built-in Plugin to explicit owner facets.
2. Remove mixed package normalization and `legacy?` fields.
3. Run core, example, benchmark, peer, docs, and Dialyzer checks.

## Acceptance matrix

| Requirement | Evidence |
| --- | --- |
| `PLG-REQ-011` to `PLG-REQ-017` | Agent schema and Plugin contract tests |
| `PLG-REQ-031`, `PLG-REQ-032`, `PLG-REQ-035` | Plugin ordering and validation tests |
| `PLG-REQ-036` to `PLG-REQ-039` | Directive ownership and runtime tests |
| `PLG-REQ-040` to `PLG-REQ-051` | Agent Server commit and Plugin lifecycle tests |
| `PLG-REQ-053` to `PLG-REQ-060` | Persistence and Topology facet tests |
