# Example Systems

The repository has executable examples under `test/examples`. Each example is a
small contract test with production-shaped code from the `examples` compile
path.

Run all examples:

```shell
mix examples
```

Run one example file while you change it:

```shell
mix test test/examples/01_basic/01_01_minimal_agent/minimal_agent_test.exs
```

## Follow the examples in order

The numbered groups add one type of complexity at a time.

| Group | Subject |
| --- | --- |
| `01_basic` | Minimal Agents, typed commands, Plugin state, Directives, and controlled Turns |
| `02_workflow` | Sequential, conditional, parallel, iterative, nested, and approval workflows |
| `03_llm` | Model responses, conversation history, tools, repair, compaction, and delegation |
| `04_runtime` | Scheduling, buses, jobs, observation, recovery, deduplication, and outboxes |
| `05_multi_agent` | Child lifecycle, requests, worker groups, hierarchies, and remote children |
| `06_factory` | Runtime-built conversations, systems, departments, and flows |
| `07_topology` | Independent, hierarchical, bus-connected, keyed, and composed systems |
| `08_applications` | Audit, subscriptions, inboxes, identity, security, coordination, and groups |

Start with `01_basic/01_01_minimal_agent`. It compares the direct Agent command
with the live actor call and verifies that both use the same route defaults.

## Use runtime examples for failure rules

The runtime group contains focused examples for the hard boundaries:

- `04_06_state_recovery` — durable state recovery
- `04_07_input_deduplication` — stable input identity
- `04_08_commit_outbox` — commit before an external effect
- `04_09_agent_observation` — semantic actor events
- `04_10_causal_trace` — trace and causation data
- `04_11_recoverable_delivery` — recoverable delivery protocol
- `04_12_pending_job_recovery` — job state after restart
- `04_13_durable_scheduling` — schedule occurrence recovery

Read the test assertions with the example module. The assertions state the
expected commit, failure, and cleanup rules.

## Research examples

`test/examples/99_research` records narrower contract investigations. These
examples cover distributed authority, fencing, checkpoint portability,
indeterminate writes, route selection, stable references, and upgrade cases.

Research examples are useful evidence for an extension design. They are not an
extra public API. Base application code on documented modules and functions.

## Build your own example

Keep one example focused on one behavior. Show the direct contract first when
possible. Add a live actor only when the example needs process, commit,
Directive, supervision, or recovery behavior. Verify failure and cleanup as
well as the successful result.
