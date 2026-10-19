# 01_07 Data-defined Agent

Import an Agent from JSON with a state Plugin and the core Scheduler Plugin.

Read [the definition and Action](data_defined_agent.ex), then the tests.
`Agent.define!/1` validates data. `Agent.instantiate!/2` adds identity and state.
`registry/0` supplies stable application identifiers for the Actions, Plugins,
schema, and option keys. JSON import resolves only those references and creates
no atoms. `CountTurns` owns one state field. The core `Jido.Plugin.Scheduler`
also starts a supervised runtime when the imported Agent starts.

```elixir
json = Jido.Examples.DataDefinedAgent.fixture_json()
{:ok, definition} = Jido.Examples.DataDefinedAgent.from_json(json)
instance = Jido.Agent.instantiate!(definition, id: "imported-counter")
{:ok, server} = Jido.start_agent(MyApp.Jido, instance)
:ok = Jido.AgentServer.await_ready(server)
request = Jido.Examples.DataDefinedAgent.schedule_signal!(0)
{:ok, _committed, _directives} = Jido.AgentServer.call(server, request)
```

`MyApp.Jido` must be a running Jido instance. The schedule request commits
before the Scheduler delivers the count command in a second Turn.

```sh
mix test test/examples/01_basic/01_07_data_defined_agent --include example --seed 0
```

Expected result: JSON round trips preserve the definition; direct and live
commands produce the same state. The imported Scheduler retains its options,
delivers a later count command, and stops with the Agent. Import with an empty
Registry or a missing Scheduler reference fails.

A document requires installed, trusted Plugin and Action code. It does not
install code or start a process. This example declares the runtime Plugin in
`extensions`; the separate static `Jido.Plugin.Scheduler.DSL` provider only
describes schedules. A one-shot timer is not durable and can be lost on restart.
Definition JSON has no instance ID or state. Complete instance JSON can also
store validated state and identity; the tests prove this round trip. A
persistence checkpoint adds revision and recovery data for an Activation and
pending work. Use persistence to recover execution.

See [Named Members](../../07_topology/07_01_independent/README.md) for a JSON
round trip that starts a composed Agent. The core authoring tests cover the
full DSL, data, and JSON format matrix.

- [Source](data_defined_agent.ex)
- [Tests](../../../test/examples/01_basic/01_07_data_defined_agent/data_defined_agent_test.exs)
- [Authoring tests](../../../test/authoring/agents/json_test.exs)
- [Scheduler import tests](../../../test/jido/agent/scheduler_codec_test.exs)

Previous: [OTP supervision](../01_05_otp_supervision/README.md) | Next: [Agent Extension](../01_09_agent_extension/README.md)

The [saved input document](fixtures/agent.json) is checked in. The Scheduler
startup test reads it directly with `registry/0`; it does not first encode a
new document. See [Plugin DSL](../../09_plugins/09_10_plugin_dsl/README.md) for
custom syntax that lowers to the same contribution format.
