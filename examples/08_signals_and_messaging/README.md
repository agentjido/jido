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
## Delivery guarantees

| Path and behavior test | Acceptance and acknowledgement | Replay and retry |
| --- | --- | --- |
| [Agent call](../06_agent_server/06_03_request_modes/request_modes_test.exs) | Turn result. A caller timeout can occur while a Turn is active. | The caller owns retries. |
| [Local PID and PubSub dispatch](08_04_dispatch_adapters/dispatch_adapters_test.exs) | The adapter accepts the dispatch or local publication. | No retained replay. The application owns retries. |
| [Bus publication](08_05_bus_publish_and_replay/bus_publish_and_replay_test.exs) | The Bus records the Signal before delivery. | The subscriber can replay recorded Signals. |
| [Durable subscription](08_06_durable_subscription/durable_subscription_test.exs) | Explicit acknowledgement advances the cursor. | An unacknowledged Signal can repeat after subscriber loss. |

Use a domain idempotency key when a retry can repeat an operation.

Run the current chapter with:

```sh
mix test.examples examples/08_signals_and_messaging --warnings-as-errors
```

Expected result: all Signal examples pass with local processes and the memory
Bus store. No adapter contacts a network service.
