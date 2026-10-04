# 01_06 Route Selection

One Agent selects an exact order route, an order wildcard, or a final fallback.

## What you will learn

- How route class and specificity give an exact route precedence over wildcards.
- How explicit priority selects between equally specific routes.
- How direct and live execution select the same route from the same Signal.

## Read the code

Read [the router Agent](route_selection.ex), then read its behavior test.

## Run it

```sh
mix test test/examples/01_basic/01_06_route_selection --include example --seed 0
```

Expected result: `order.create` uses the exact route even though broad routes
were declared first. Another order command uses the single wildcard, equal
exact routes use priority, and unrelated input uses the fallback. Direct and
live execution produce the same state for each Signal.

## Important behavior

Jido orders matches by exact, single-wildcard, and multi-wildcard route class.
It then uses pattern complexity, higher explicit priority, and registration
order. Selection happens before Jido prepares or runs the route Action. Use a
`**` route only when the Agent has a defined fallback policy. Without one,
unmatched input returns `Jido.Error.RoutingError`.

## Limits

This example does not build a second application dispatcher. It uses the Agent
route table as the command boundary.

## Files

- [Source](route_selection.ex)
- [Tests](../../../test/examples/01_basic/01_06_route_selection/route_selection_test.exs)

Previous: [OTP Supervision](../01_05_otp_supervision/README.md) | Next: [Workflow examples](../../02_workflow/README.md)
