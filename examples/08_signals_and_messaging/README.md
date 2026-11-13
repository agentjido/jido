# 08 Signals and Messaging

These offline lessons follow Signals from construction through routing,
delivery, replay, acknowledgement, and trace propagation.

1. [Signal Envelope](08_01_signal_envelope/README.md) defines one custom
   CloudEvents-compatible Signal.
2. [Signal Schema and Context](08_02_signal_schema_and_context/README.md)
   separates validated domain data from flat transport context.
3. [Router Precedence](08_03_router_precedence/README.md) compares exact,
   single-segment, and multi-segment routes.
4. [Dispatch Adapters](08_04_dispatch_adapters/README.md) validates and runs
   local delivery targets.
5. [Bus Publish and Replay](08_05_bus_publish_and_replay/README.md) stores each
   Signal before ordered local delivery.
6. [Durable Subscription](08_06_durable_subscription/README.md) proves
   acknowledgement and repeated delivery after subscriber loss.
7. [Trace and Causation](08_07_trace_and_causation/README.md) carries one W3C
   trace through child work and a reply.
8. [Follow One Signal](08_08_follow_one_signal/README.md) traces a correlated
   request through coordinator and worker Turns, uncertain delivery, retry,
   deduplication, and reply.
9. [Delivery Guarantees](08_09_delivery_guarantees/README.md) compares
   acceptance, retention, acknowledgement, retry, and duplicate boundaries.

Run the current chapter with:

```sh
mix test.examples examples/08_signals_and_messaging --warnings-as-errors
```

Expected result: all Signal examples pass with local processes and the memory
Bus store. No adapter contacts a network service.

