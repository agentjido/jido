# 01_06 Route Selection

One Agent selects an exact order route, an order wildcard, or a final fallback.

## What you will learn

- How the first matching route in declaration order selects the handler.
- Why specific routes must come before broader routes and the fallback.
- How direct and live execution select the same route from the same Signal.

## Read the code

Read [the router Agent](route_selection.ex), then read its behavior test.

## Run it

```sh
mix test test/examples/01_basic/01_06_route_selection --include example --seed 0
```

Expected result: `order.create` uses the first, exact route. Another order
command uses the next, single-wildcard route. Unrelated input uses the final
fallback. Direct and live execution produce the same state for each Signal.
A separate test moves the wildcard first and proves that it then wins for
`order.create`.

## Important behavior

Jido selects the first matching route in declaration order. Exact routes have
no automatic preference over wildcard routes. Route paths must be unique.
Selection happens before Jido prepares or runs the route Action. A handler
failure does not cause Jido to try the next route.

Use a `**` route only when the Agent has a defined fallback policy, and put it
last. Without a matching route, the command returns
`%Jido.Agent.Error{code: :unmatched_input}`.

## Limits

This example does not build a second application dispatcher. It uses the Agent
route table as the command boundary.

## Files

- [Source](route_selection.ex)
- [Tests](../../../test/examples/01_basic/01_06_route_selection/route_selection_test.exs)

Pass-through and transform routes are shown in
[Direct Connections](../../07_topology/07_11_direct_connections/README.md).
They emit Signals rather than changing domain state. Routes select the first
match; output connections select all matching edges.

Previous: [Typed Command Agent](../01_02_typed_command_agent/README.md) | Next: [Plugin State Agent](../01_03_plugin_state_agent/README.md)
