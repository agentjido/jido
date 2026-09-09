# FA-01: Route precedence and fixed selection

Status: **Core feature required**.

Baseline on 2026-09-05: 2 passing and 2 failing checks.
As of 2026-09-07, the failing tests are temporarily skipped, with reasons.
The original assertions remain. See the [research test policy](../README.md).

## Feature and proof

A single route works in direct and live execution. The fallback handles an unrelated Signal. An exact route plus wildcards returns a RoutingError with three targets. A preparation Plugin changes the selected handler from create to cancel.

## Required change

Select the first route by Router precedence from the source Signal. Keep that executable fixed through Plugin preparation.

## Scope

The probe uses three explicit Agent DSL definitions and cmd/3. Route defaults and the preparation Plugin are declared in the DSL. It does not replace routing with an example-owned dispatcher.

## Run

From the jido repository:

```sh
mix test test/examples/99_research/99_09_route_selection --include example --seed 0
```

This is a secondary check. The missing-contract tests remain skipped until
the feature is implemented. Do not reverse the original assertions.

[Source](../../../../examples/99_research/99_09_route_selection/route_selection.ex) · [Tests](route_selection_test.exs)
