# 01_05 OTP Supervision

An application supervisor owns a Jido instance and an AgentServer activation.
The activation owns the Server worker and Plugin roots in one `:one_for_all`
group. A failed worker is replaced from the instance's accepted checkpoint.

## What you will learn

- How `use Jido` binds the instance facade.
- How `Jido.AgentServer.child_spec/1` starts an activation supervisor.
- How worker replacement differs from clean activation shutdown.

## Read the code

Read [the counter](example.ex), [the Application](application.ex), then
[the integration test](../../../test/examples/01_basic/01_05_otp_supervision/example_test.exs).

## Run it

```sh
mix test test/examples/01_basic/01_05_otp_supervision --include example --seed 0
```

Expected result: a worker restart retains count seven and revision one. Its old
Plugin roots stop. Clean activation shutdown stays stopped. An explicit new
activation starts at zero because this example has no durable adapter.

```elixir
alias Jido.Examples.OTPSupervision.{Application, Counter}
alias Jido.Examples.OTPSupervision.Jido, as: Runtime
{:ok, app} = Application.start(:normal, [])
server = Runtime.whereis_agent("otp-counter")
:ok = Jido.AgentServer.await_ready(server)
{:ok, signal} = Counter.increment_signal(%{amount: 7})
{:ok, agent, []} = Jido.AgentServer.call(server, signal)
agent.state # %{count: 7}
Supervisor.which_children(Jido.AgentServer.activation(server))
:ok = Supervisor.stop(app)
```

## Process tree and ownership

```text
Application supervisor (:rest_for_one)
├── Jido instance infrastructure
└── AgentServer supervisor (:transient activation)
    ├── AgentServer worker
    └── Scheduler Plugin root
```

Infrastructure starts first and stops last. `:rest_for_one` replaces the
activation when its infrastructure is replaced. The activation uses
`:one_for_all` so its worker and required Plugin roots recover together.
`Server.children/1` reports owned Agents, not Plugin roots. Use ordinary OTP
supervisor inspection to view Plugin processes.

## Limits

The local checkpoint survives worker failure within the same Jido instance.
Clean activation shutdown clears it. Configure persistence for complete instance
or BEAM loss. An interrupted uncommitted Turn is not recovered. This example
does not provide distributed ownership or durable external delivery.

Previous: [Directive Agent](../01_04_directive_agent/README.md) | Next: [Data-defined Agent](../01_07_data_defined_agent/README.md)
