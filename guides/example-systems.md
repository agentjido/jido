# Example Systems

The repository has executable examples under `test/examples`. Each example is a
small contract test with production-shaped code from the `examples` compile
path.

Run all examples:

```shell
mix test.examples
```

Run one example file while you change it:

```shell
mix test test/examples/01_basic/01_01_minimal_agent/minimal_agent_test.exs
```

## Follow the examples in order

The numbered groups add one type of complexity at a time.

| Group | Subject |
| --- | --- |
| `01_basic` | Minimal Agents, typed commands, Plugin-owned fields, Directives, and controlled Turns |
| `02_workflow` | Sequential, conditional, parallel, iterative, nested, and approval workflows |
| `03_llm` | Model responses, conversation history, tool use, parallel tools, and repair |
| `04_runtime` | Scheduling, buses, managed jobs, inspection, observation, and recovery |
| `05_multi_agent` | Child lifecycle, requests, worker groups, hierarchies, and remote children |
| `06_factory` | Runtime-built conversations, systems, departments, and flows |
| `07_topology` | Independent, hierarchical, bus-connected, keyed, composed, and Plugin-contributed systems |
| `08_applications` | Audit, subscriptions, inboxes, purpose loops, and groups |
| `09_plugins` | Pure preparation, live admission, identity, encrypted Signals, and composition |

Start with `01_basic/01_01_minimal_agent`. It compares the direct Agent command
with the live actor call and verifies that both use the same route defaults.

## Use runtime examples for failure rules

The runtime group contains focused examples for the hard boundaries:

- `04_06_state_recovery` — durable state recovery
- `04_07_agent_observation` — semantic actor events
- `04_08_causal_trace` — trace and causation data
- `04_09_recoverable_delivery` — recoverable delivery protocol
- `04_10_pending_job_recovery` — job state after restart
- `04_11_durable_scheduling` — schedule occurrence recovery
- `04_12_stable_reference` — durable identity across process replacement
- `04_13_turn_upgrade` — serialized release installation
- `04_14_state_migration` — atomic domain and Plugin state migration

Read the test assertions with the example module. The assertions state the
expected commit, failure, and cleanup rules.

## Research examples

`test/examples/99_research` retains the distributed-authority investigation.
It shows an external fencing workaround because Jido does not provide
cluster-exclusive ownership.

Research examples are useful evidence for an extension design. They are not an
extra public API. Base application code on documented modules and functions.

## Build your own example

Keep one example focused on one behavior. Show the direct contract first when
possible. Add a live actor only when the example needs process, commit,
Directive, supervision, or recovery behavior. Verify failure and cleanup as
well as the successful result.
