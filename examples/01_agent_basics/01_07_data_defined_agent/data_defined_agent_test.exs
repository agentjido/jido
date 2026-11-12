Code.require_file("data_defined_agent.ex", __DIR__)

defmodule Jido.Examples.Basic.DataDefinedAgentTest do
  use Jido.Test.Case, async: true
  @moduletag :integration

  alias Jido.Agent
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.DataDefinedAgent, as: Example
  alias Jido.Plugin.Scheduler

  test "data and JSON definitions use the same direct and live contract", %{jido: jido} do
    {document, registry} = Example.encode()

    assert {:ok, definition} =
             Jido.Test.AgentServer.Registry.decode(Jason.decode!(Jason.encode!(document)), registry)

    assert definition == Example.definition()
    direct = Agent.instantiate!(definition, id: unique_id("direct"))
    live = Agent.instantiate!(definition, id: unique_id("live"))
    {:ok, server} = Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, live)
    assert :ok = Server.await_ready(server)
    assert {:ok, candidate, []} = Agent.cmd(direct, Example.signal!(3))

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Server.call(server, Example.signal!(3))

    committed = Server.snapshot(server).agent
    assert candidate.state == %{count: 3, turns: 1, scheduler: %{cron: %{}}}
    assert committed.state == candidate.state
  end

  test "an imported Scheduler declaration starts its runtime and delivers a later command", %{
    jido: jido
  } do
    assert %Jido.Catalog{} = Example.registry()
    assert {:ok, definition} = Example.from_json(Example.fixture_json())
    assert definition.id == nil
    assert definition.state == nil

    assert Enum.map(definition.plugins, &{&1.provider, &1.data}) == [
             {Example.CountTurns, %{}},
             {Scheduler, %{retry_delay_ms: 25}}
           ]

    instance = Agent.instantiate!(definition, id: unique_id("json-scheduler"))
    assert {:ok, server} = Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, instance)
    assert :ok = Server.await_ready(server)
    assert Server.snapshot(server).agent.state.scheduler == %{cron: %{}}

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Server.call(server, Example.schedule_signal!(0))

    scheduled = Server.snapshot(server).agent
    assert scheduled.state.count == 0
    assert scheduled.state.turns == 1
    eventually(fn -> Server.snapshot(server).agent.state.count == 1 end)
    assert Server.snapshot(server).agent.state.turns == 2

    activation = Jido.Test.AgentServer.ExampleRuntime.activation(server)
    monitor = Process.monitor(activation)
    assert :ok = Jido.stop_agent(jido, server)
    assert_receive {:DOWN, ^monitor, :process, ^activation, _}
  end

  test "Scheduler configuration must have an allowed Plugin reference" do
    {document, _registry} = Example.encode()
    missing_scheduler = Jido.Catalog.new!([])

    assert {:error, _} =
             Jido.Codec.decode_json(JSON.encode!(document),
               catalog: missing_scheduler,
               codec: Jido.Agent.Codec
             )
  end

  test "a document cannot resolve references outside its trusted Registry" do
    {document, _registry} = Example.encode()

    assert {:error, _} =
             Jido.Codec.decode(document, catalog: Jido.Catalog.new!([]), codec: Jido.Agent.Codec)
  end

  test "instance JSON writes only the portable definition" do
    assert {:ok, definition} = Example.from_json(Example.fixture_json())
    assert definition.id == nil and definition.state == nil
    instance = Agent.instantiate!(definition, id: "stored-counter")
    assert {:ok, changed, []} = Agent.cmd(instance, Example.signal!(3))
    assert {:ok, document} = Jido.Test.AgentServer.Registry.encode(changed, Example.registry())
    assert {:ok, restored} = Example.from_json(Jason.encode!(document))
    assert restored == definition
    assert restored.id == nil and restored.state == nil
  end
end
