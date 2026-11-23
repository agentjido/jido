# 26_06 Route to one fixed home

Start one Jido instance on two connected BEAMs. Both callers increment the
same counter on one activation.

## What you will learn

- Configure `cluster: [home: node, generation: generation]` on a Jido instance.
- Use `Jido.call/4`, `Jido.cast/3` and `Jido.status/3` on either node.
- Reconcile an unknown mutation after a lost reply.

## Read the code

Read the [instance configuration](example.ex), then the [two-peer tests](example_test.exs).

## Run it

`mix test.examples examples/26_distributed_agents/26_06_native_fixed_home --warnings-as-errors`

Two concurrent calls advance consecutive revisions on one activation. The
ingress peer stays empty. During link loss the home keeps its role. After
reconnect, the accepted Turn's change is visible once.

## Important behavior

Ingress starts before the home and without a usable local Store. A direct
activation or child startup on ingress fails. The test also refuses an
externally supervised activation on the home. One bounded fault gate holds
an accepted Turn while the test cuts the link or waits for the caller timeout.

## Limits

The Store in this lesson uses local ETS. Its data disappears when the
home BEAM stops. Fixed-home routing does not promote the ingress peer.

## Core Fit and Gaps

Instance routing and stable Addresses provide the core path. The application
owns node discovery, the configured home, and reconciliation of unknown outcomes.

## Files

- [Source](example.ex)
- [Tests](example_test.exs)
- [Counter](../support/counter.ex)
- [Fault gate](../support/turn_start_gate.ex)

[Previous](../26_05_partition_without_ownership/README.md) · [Next](../26_07_native_ticket_recovery/README.md)
