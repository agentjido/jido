# 01_05 OTP supervision

Place an Agent directly in an application supervision tree and recover its
committed state after an abnormal process exit.

## What you will learn

- How to use `Jido.AgentServer.child_spec/1` with explicit Agent and child IDs.
- How OTP restart, local state recovery, and Plugin cleanup work together.
- When ordinary supervision is sufficient without a Topology.

## Read the code

Read [the counter](example.ex), then [the Application](application.ex), then
[the integration test](../../../test/examples/01_basic/01_05_otp_supervision/example_test.exs).
In a standalone Mix project, select the Application with
`mod: {Jido.Examples.OTPSupervision.Application, []}`.

## Run it

```sh
mix test test/examples/01_basic/01_05_otp_supervision --include example --seed 0
```

Expected result: a Signal commits `count: 7` at revision 1. The test kills the
Agent. OTP starts a new PID with the same `otp-counter` ID, count, and revision.
The old Scheduler runtime stops, and the replacement gets a new runtime.
A clean stop leaves the child stopped. An explicit OTP restart then starts at
zero because this example has no durable persistence. Application shutdown
stops the Agent, its Plugin processes, and its Jido infrastructure.

For interactive use, run `iex -S mix` and execute:

```elixir
alias Jido.Examples.OTPSupervision.{Application, Counter}
{:ok, app} = Application.start(:normal, [])
jido = Jido.Examples.OTPSupervision.Jido
{:counter, server, _, _} = List.keyfind(Supervisor.which_children(app), :counter, 0)
:ok = Jido.AgentServer.await_ready(server)
{:ok, signal} = Counter.increment_signal(%{amount: 7})
{:ok, _agent} = Jido.AgentServer.call(server, signal)
Process.exit(server, :kill)
# After OTP restarts the child:
Supervisor.which_children(app)
server = Jido.whereis_agent(jido, "otp-counter")
Jido.AgentServer.snapshot(server)
Jido.AgentServer.children(server)
:ok = Supervisor.stop(app)
```

## Process tree and ownership

The running tree has this structure. `Supervisor.which_children/1` shows the
application and infrastructure children. `AgentServer.children/1` shows the
Scheduler runtime and its lifecycle wrapper PIDs.

```text
Application supervisor (:rest_for_one)
├── Jido.Examples.OTPSupervision.Jido
│   ├── TaskSupervisor
│   ├── RegistrationGuard
│   ├── Registry (and its partitions)
│   ├── RuntimeStore
│   ├── SpawnRegistry
│   └── AgentSupervisor (DynamicSupervisor)
│       └── Scheduler lifecycle wrapper (linked to the counter)
│           └── private Supervisor
│               └── Scheduler runtime
└── :counter (AgentServer, stable Agent ID "otp-counter")
```

The Scheduler has no scheduled jobs here. It makes the standard Plugin runtime
ownership visible. Its wrapper stays in Jido infrastructure, links to its Agent,
and stops its runtime subtree when that Agent exits. No Topology starts.

## Important behavior

Infrastructure starts first. `:rest_for_one` makes the Agent restart if its
Jido infrastructure is replaced. Shutdown runs in reverse order. The Agent
child uses `:transient`: abnormal exits restart; `:normal`, `:shutdown`, and
hibernation stay stopped. `Jido.stop_agent/2` uses a clean shutdown. The
supervisor retains the stopped child spec for an explicit
`Supervisor.restart_child(app, :counter)`.

The Jido runtime checkpoint records committed state before it becomes visible.
It survives Agent failure while the same Jido instance is alive. It is cleared
on a clean Agent stop and lost on complete instance or node loss. Configure a
[persistence adapter](../../../guides/persistence-adapters.livemd) for recovery
across those events. An interrupted uncommitted Turn is not recovered.

## Limits

This example proves local supervision and cleanup. It does not prove durable
recovery, distributed ownership, or delivery of external effects. Three
restarts in five seconds is the application restart limit.

Ordinary supervision is sufficient for a fixed set of Agents. Use
[Topology](../../../guides/topology-supervision.md) for group expansion, graph
validation, declared connections, aggregate readiness, or target changes.

## Files

- [Agent](example.ex)
- [Application](application.ex)
- [Integration test](../../../test/examples/01_basic/01_05_otp_supervision/example_test.exs)
- [Shared test setup](../../../test/examples/support/basic_sdk_case.ex)

Previous: [Directive Agent](../01_04_directive_agent/README.md) | Next: [Route Selection](../01_06_route_selection/README.md)
