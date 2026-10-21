defmodule JidoTest.Examples.Basic.DataDefinedAgentTest do
  use JidoTest.Case, async: true
  @moduletag :example

  alias Jido.Agent
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.DataDefinedAgent, as: Example
  alias Jido.Plugin.Scheduler

  test "data and JSON definitions use the same direct and live contract", %{jido: jido} do
    {document, registry} = Example.encode()

    assert {:ok, definition} =
             JidoTest.AgentRegistry.decode(Jason.decode!(Jason.encode!(document)), registry)

    assert definition == Example.definition()
    direct = Agent.instantiate!(definition, id: unique_id("direct"))
    live = Agent.instantiate!(definition, id: unique_id("live"))
    {:ok, server} = JidoTest.ExampleRuntime.start_agent(jido, live)
    assert :ok = Server.await_ready(server)
    assert {:ok, candidate, []} = Agent.cmd(direct, Example.signal!(3))
    assert {:ok, committed, []} = Server.call(server, Example.signal!(3))
    assert candidate.state == %{count: 3, turns: 1, scheduler: %{cron: %{}}}
    assert committed.state == candidate.state
  end

  test "an imported Scheduler declaration starts its runtime and delivers a later command", %{
    jido: jido
  } do
    assert %Jido.Authoring.Registry{} = Example.registry()
    assert {:ok, definition} = Example.from_json(Example.fixture_json())
    assert definition.id == nil
    assert definition.state == nil

    assert Agent.runtime_plugins(definition) == [
             {Example.CountTurns, []},
             {Scheduler, [retry_delay_ms: 25]}
           ]

    instance = Agent.instantiate!(definition, id: unique_id("json-scheduler"))
    assert {:ok, server} = JidoTest.ExampleRuntime.start_agent(jido, instance)
    assert :ok = Server.await_ready(server)
    assert {:ok, %{cron: %{}}} = Server.plugin_state(server, Scheduler)

    assert {:ok, scheduled, [%Scheduler.Schedule{}]} =
             Server.call(server, Example.schedule_signal!(0))

    assert scheduled.state.count == 0
    assert scheduled.state.turns == 1
    eventually(fn -> Server.agent(server).state.count == 1 end)
    assert Server.agent(server).state.turns == 2

    activation = Server.activation(server)
    monitor = Process.monitor(activation)
    assert :ok = Jido.stop_agent(jido, server)
    assert_receive {:DOWN, ^monitor, :process, ^activation, _}
  end

  test "Scheduler configuration must have an allowed Plugin reference" do
    {document, registry} = Example.encode()
    missing_scheduler = Map.delete(registry.entries, "plugins/scheduler/v1")

    assert {:error, _} =
             JidoTest.AgentRegistry.decode_json(Jason.encode!(document), missing_scheduler)
  end

  test "a document cannot resolve references outside its trusted Registry" do
    {document, _registry} = Example.encode()
    assert {:error, _} = JidoTest.AgentRegistry.decode(document, %{})
  end

  test "instance JSON writes only the portable definition" do
    assert {:ok, definition} = Example.from_json(Example.fixture_json())
    assert definition.id == nil and definition.state == nil
    instance = Agent.instantiate!(definition, id: "stored-counter")
    assert {:ok, changed, []} = Agent.cmd(instance, Example.signal!(3))
    assert {:ok, document} = JidoTest.AgentRegistry.encode(changed, Example.registry())
    assert {:ok, restored} = Example.from_json(Jason.encode!(document))
    assert restored == definition
    assert restored.id == nil and restored.state == nil
  end
end
