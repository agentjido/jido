# FA-01: Route precedence and fixed selection

Status: **Core feature available**.

Result on 2026-09-09: 4 passing checks. No check is skipped.

## Feature and proof

A single route works in direct and live execution. The fallback handles an
unrelated Signal. An exact route wins before wildcard routes. The source Signal
fixes the executable for direct and live evaluation.

## Implemented contract

Select the first route by Router precedence from the source Signal. Keep that
executable fixed through execution.

## Scope

The probe uses three explicit Agent DSL definitions and `cmd/3`. Route defaults
are declared in the DSL. It does not replace routing with an example-owned
dispatcher.

## Run

From the jido repository:

```sh
mix test test/examples/99_research/99_09_route_selection --include example --seed 0
```

This command must pass with no skipped check.

[Source](../../../../examples/99_research/99_09_route_selection/route_selection.ex) · [Tests](route_selection_test.exs)
