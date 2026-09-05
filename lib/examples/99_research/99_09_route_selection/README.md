# FA-01: Route precedence and fixed selection

Status: **Core feature required**.

Result on 2026-09-05: **2 passing checks; 2 failing acceptance checks.** All checks are enabled.

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

This command returns a failing status until the stated core contract exists. Do not skip the assertion or reverse it to accept the current limitation.

[Source](route_selection.ex) · [Tests](../../../../test/examples/99_research/99_09_route_selection/route_selection_test.exs) · [Complete result log](../../../../docs/examples/feature-acceptance-results.md)
