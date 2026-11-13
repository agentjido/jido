# 08_03 Router Precedence

One immutable Router returns exact and wildcard targets in stable precedence
order.

## What you will learn

- How exact, `*`, and `**` paths match a Signal type.
- How routing returns targets without executing them.

## Read the code

Read [the Router](router_precedence.ex), then read
[the tests](router_precedence_test.exs).

## Run it

`mix test.examples examples/08_signals_and_messaging/08_03_router_precedence --warnings-as-errors`

Expected result: an order-created Signal matches four targets from most
specific to least specific.

## Important behavior

Registration order breaks ties after path specificity and priority.

## Limits

A Router selects generic targets. Dispatch owns target validation and delivery.

## Files

- [Router](router_precedence.ex)
- [Tests](router_precedence_test.exs)

