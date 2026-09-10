# Core scope and extension points

This guide describes the implemented `v3-spike` API. The files in
`docs/design` contain deferred proposals and implementation notes. Use this
guide and the public module documentation when you build an extension.

## Supported core

| Area | Supported contract |
| --- | --- |
| Agent values | Immutable definitions and instances, validated state, Actions, Flows, and Directives. Direct commands return a candidate; a live Server commits it. |
| Authoring | Declarative modules, map and keyword declarations, Builder, and trusted Codecs share core validation. These forms remain supported. |
| Live execution | Public PID-based `Jido.AgentServer` operations. `Jido` instance helpers start, find, stop, hibernate, and thaw Agents. An explicit upgrade operation waits for idle; validated definition migration preserves identity and Plugin declarations. |
| Plugins | One callback-free package manifest can select Agent, Agent Server, Persistence, and Topology owner facets. Each facet has bounded authority. |
| Persistence | Binary get and exact-byte CAS, versioned active and tombstone records, revision-zero creation, legacy active reads, and Agent-owned checkpoints. |
| Agent relationships | Local owned children and explicit targeting of a known Erlang node. |
| Topology | Pure definitions and plans, ordered static Plugin contribution, bounded local activation, readiness, same-target repair, additive local Agent updates, and cleanup. |

An extension uses these public APIs and the selection rules in the
[extension-boundaries guide](extension-boundaries.md).
<code>Jido.Plugin.Spec</code>, all four owner-facet Specs,
<code>Jido.AgentServer.ChildInfo</code>, <code>Jido.AgentServer.ParentRef</code>,
and <code>Jido.RuntimeStore</code> are internal implementation details. Use the
public Plugin manifest, owner behaviors and callback values, inspection maps,
relationship functions, and instance helpers instead.

If an extension needs private Server state, private messages, generated
supervisor names, or an ETS table layout, first add an integration example that
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

Use `Jido.Topology.Controller.update/3` to add local Agent entries to a ready
controller. The Topology ID, resources, and all existing Agent specifications
must stay identical. The new target becomes the source for later repair passes.
Removal, changed definitions, resource changes, placement, and ownership
transfer require controller replacement or another control plane.

The independent topology example stops one Agent. In manual mode, it remains
stopped until the application requests repair. The other Agent keeps its PID
and state. See the
[example test](https://github.com/agentjido/jido/blob/v3-spike/test/examples/07_topology/07_01_independent/independent_test.exs).

This operation repairs the existing target. Use `update/3` for additive local
growth. Destructive changes, placement, and ownership transfer require separate
contracts.

## Deferred scope

Future package names describe possible ownership, not implemented packages:

| Concern | Proposed owner or next decision |
| --- | --- |
| Database clients, recovery scans, leases, fencing, and retention | A durable extension such as `jido_durable`. Core keeps its storage and commit contract. |
| Membership, placement, rebalance, and failover | A cluster extension such as `jido_cluster`. Durable authority must come from storage or an explicit authority service. |
| Transport gateways, authentication, and durable inboxes | A transport extension such as `jido_fabric`. |
| Catch-up queues, backoff, and scheduling policy | An application or Scheduler extension, with a failing integration example before another core control is added. |
| Private Server or Plugin runtime migration and destructive Topology updates | A separate design and acceptance pass. Core upgrade keeps Plugin declarations fixed, and Topology update adds local Agents only. |

The research suite records executable contracts for replacement Init, stable
namespace identity, durable deletion, the explicit quiescent upgrade boundary,
validated Agent definition migration, and additive Topology updates. It also
proves source-Signal route selection and Plugin-owned state isolation. See the current
[research test matrix](../test/examples/99_research/README.md).
The distributed authority example uses an explicit external authority; it does
not prove that core elects one cluster owner.

## Package and test boundary

`examples/` compiles only in development and test. Its tests use the shared
`:example` tag and are excluded by default. `req_llm` and `dotenvy` are also
development and test dependencies. They are absent from the Hex requirements
and the production dependency graph.

Run core tests and static checks by default:

```sh
mix quality
```

Benchmark tests (`mix benchmarks --seed 0`) and example tests are separate,
secondary checks. Run focused extension examples when needed:

```sh
mix test test/jido/agent/scheduled_occurrence_recovery_test.exs \
  test/jido/topology test/examples/07_topology \
  test/examples/08_applications --include example --seed 0
```

Run all examples separately with `mix examples --seed 0`. All example tests
pass without skips. See the
[test policy](https://github.com/agentjido/jido/blob/v3-spike/guides/testing.md).
