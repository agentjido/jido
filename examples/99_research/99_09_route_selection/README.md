# 99_09 Route Selection

Status: implemented routing contract; candidate for the stable basic section.

Three Agent definitions compare one route, wildcard fallback, and fixed exact
selection in direct and live execution.

## What this proves

- Router precedence selects an exact route before matching wildcards.
- The source Signal fixes the executable for the complete evaluation.

## Read the code

Read [the three Agent definitions and shared Action](route_selection.ex).

## Run it

```sh
mix test test/examples/99_research/99_09_route_selection --include example --seed 0
```

Expected result: direct and live execution select the same handler, exact routes
win, and unrelated input reaches the fallback.

## Gap and limits

The public contract exists. Promote the smallest useful route-precedence lesson
to `01_basic`, then remove this research copy. This probe does not define an
application-owned dispatcher.

## Files

- [Source](route_selection.ex)
- [Tests](../../../test/examples/99_research/99_09_route_selection/route_selection_test.exs)

Previous: [Indeterminate Write](../99_08_indeterminate_write/README.md) | Next: [Plugin Isolation](../99_10_plugin_isolation/README.md)
