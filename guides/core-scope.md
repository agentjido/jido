# Core scope and extension points

This guide describes the implemented `v3-spike` API. The files in
`docs/design` contain deferred proposals and implementation notes. Use this
guide and the public module documentation when you build an extension.

## Supported core

| Area | Supported contract |
| --- | --- |
| Agent values | Immutable definitions and instances, validated state, Actions, Flows, and Directives. Direct commands return a candidate; a live Server commits it. |
| Authoring | Spark DSL, map and keyword construction, Builder, and trusted Codecs share core validation. These forms remain supported. |
| Live execution | Public PID-based `Jido.AgentServer` operations. `Jido` instance helpers start, find, stop, hibernate, and thaw Agents. |
| Plugins | Declared owned state, preparation, admission, state updates, post-commit dispatch, and optional supervised runtimes. |
| Persistence | The binary `Jido.Persistence.Adapter` contract, atomic compare-and-swap, and existing checkpoint and restore rules. |
| Agent relationships | Local owned children and explicit targeting of a known Erlang node. |
| Topology | Pure definitions and plans, bounded local activation, readiness, repair, and cleanup. |

An extension uses these public APIs. If it needs private Server state, private
messages, or generated supervisor names, first add an integration example that
shows the missing core operation. Keep the core change as small as that proof
permits.

## Scheduler delivery interval

An Agent can set the delay between attempts to deliver saved pending work:

```elixir
agent do
  plugin Jido.Plugin.Scheduler,
    config: [delivery_interval: 250]
end
```

Add this Plugin declaration to the Agent's `agent` block. The value is
milliseconds, from 1 through 4,294,967,295. The default is 100.
The delay starts when the previous attempt finishes. Activation and newly
queued work can start an immediate attempt. `delivery_timeout` separately
limits each state read and delivery call. `retry_delay_ms` separately controls
retry after a runtime schedule fails to start.

The interval changes delivery timing. The Scheduler still retains at most one
pending occurrence per job, skips later slots while it is pending, and retries
the saved occurrence until its result commit acknowledges it. The occurrence
ID remains stable across attempts. A receiver must use that ID to handle
duplicate external work.

The durable scheduling integration test rejects result writes, checks the
configured delay, then permits a write. It verifies that the same saved work
commits once and that the acknowledgement clears it. See the
[recovery tests](https://github.com/agentjido/jido/blob/v3-spike/test/jido/agent/scheduled_occurrence_recovery_test.exs).

## Topology repair timing

Applications can control when a local controller repeats its repair pass:

```elixir
alias Jido.Topology.Controller

{:ok, controller} = Controller.start_link(
  jido: MyApp.Jido,
  topology: instance,
  repair: :manual
)

:ok = Controller.await_ready(controller)

# Call after the application decides to repair the existing target.
:ok = Controller.reconcile(controller)
:ok = Controller.await_ready(controller)
```

The default is `repair: :automatic`. It repeats passes at the definition's
`startup.retry_interval`. Manual mode performs initial startup once and then
waits for explicit requests. Child supervision and Plugin runtime recovery
continue in both modes.

`reconcile/2` returns `:ok` when the request is accepted. Use `await_ready/2`
to wait for completion and `status/2` to inspect errors. Requests during an
active pass produce one follow-up pass. They share the controller's startup
concurrency limit. Healthy Agents retain their PIDs and committed state.

The independent topology example stops one Agent. In manual mode, it remains
stopped until the application requests repair. The other Agent keeps its PID
and state. See the
[example test](https://github.com/agentjido/jido/blob/v3-spike/test/examples/07_topology/07_01_independent/independent_test.exs).

This operation repairs the existing target. Live definition changes, topology
resizing, placement, and ownership transfer require separate contracts.

## Deferred scope

Future package names describe possible ownership, not implemented packages:

| Concern | Proposed owner or next decision |
| --- | --- |
| Database clients, recovery scans, leases, fencing, and retention | A durable extension such as `jido_durable`. Core keeps its storage and commit contract. |
| Membership, placement, rebalance, and failover | A cluster extension such as `jido_cluster`. Durable authority must come from storage or an explicit authority service. |
| Transport gateways, authentication, and durable inboxes | A transport extension such as `jido_fabric`. |
| Catch-up queues, backoff, and scheduling policy | An application or Scheduler extension, with a failing integration example before another core control is added. |
| Agent migration and live topology updates | A separate design and acceptance pass. A repair request does not implement an upgrade. |

The research suite still records missing proposed contracts for route
selection, Plugin input isolation and replacement Init, stable namespace
identity, definition revisions, durable deletion, and live upgrades. See the
[feature results](https://github.com/agentjido/jido/blob/v3-spike/docs/examples/feature-acceptance-results.md)
and [upgrade results](https://github.com/agentjido/jido/blob/v3-spike/docs/examples/live-upgrade-results.md).
The distributed authority example uses an explicit external authority; it does
not prove that core elects one cluster owner.

## Package and test boundary

`examples/` compiles only in development and test. Its tests use the shared
`:example` tag and are excluded by default. `req_llm` and `dotenvy` are also
development and test dependencies. They are absent from the Hex requirements
and the production dependency graph.

Run the focused extension checks with:

```sh
mix test test/jido/agent/scheduled_occurrence_recovery_test.exs \
  test/jido/topology test/examples/07_topology \
  test/examples/08_applications --include example --seed 0
```

Run all examples with `mix examples`. The full acceptance suite includes the
enabled research failures: `mix test --include example --include flaky --seed 0`.
