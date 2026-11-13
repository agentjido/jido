# 08_04 Dispatch Adapters

One Signal is delivered to PID, custom, and no-op targets. An HTTP target is
validated but is not called.

## What you will learn

- How Dispatch validates target options before delivery.
- How an application implements a custom adapter.

## Read the code

Read [the target set and adapter](dispatch_adapters.ex), then read
[the tests](dispatch_adapters_test.exs).

## Run it

`mix test.examples examples/08_signals_and_messaging/08_04_dispatch_adapters --warnings-as-errors`

Expected result: the two local delivery targets receive the same Signal in
order. HTTP validation makes no network request.

## Important behavior

Dispatch is synchronous and ordered. The caller owns retry, concurrency, and
circuit-breaking policy.

## Limits

This lesson does not contact HTTP or PubSub services. It does not prove remote
delivery.

## Core Fit and Gaps

PID, no-op, and custom targets use one public Dispatch boundary. Offline tests
can validate an HTTP target but cannot prove its transport behavior without a
network service. That proof belongs to an adapter conformance suite, not this
offline chapter.

## Files

- [Targets and adapter](dispatch_adapters.ex)
- [Tests](dispatch_adapters_test.exs)
