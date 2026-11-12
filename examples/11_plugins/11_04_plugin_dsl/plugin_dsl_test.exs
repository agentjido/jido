Code.require_file("thresholds.ex", __DIR__)
Code.require_file("plugin_dsl.ex", __DIR__)

defmodule Jido.Examples.Plugins.DSLTest do
  use Jido.Test.Case, async: true
  @moduletag :integration

  alias Jido.Agent, as: CoreAgent
  alias Jido.AgentServer, as: Server
  alias Jido.Catalog
  alias Jido.Examples.Plugins.DSL.{Agent, Thresholds}

  test "Plugin syntax lowers to portable data and adds owned state", %{jido: jido} do
    definition = Agent.definition()

    assert [%{id: "examples.thresholds", provider: Thresholds, vsn: 1, data: data}] =
             definition.plugins

    assert data == %{
             on: "examples.plugins.dsl.add",
             thresholds: [%{name: :first, at: 1}, %{name: :third, at: 3}]
           }

    {:ok, signal} = Agent.add_signal(%{amount: 3})
    agent = Agent.instantiate!(id: unique_id())
    assert {:ok, direct, []} = Agent.cmd(agent, signal)
    assert direct.state == %{count: 3, reached: [:first, :third]}
    {:ok, server} = Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, agent)
    assert {:ok, ^direct, []} = Server.call(server, signal)
    assert {:ok, again, []} = Server.call(server, signal)
    assert again.state == %{count: 6, reached: [:first, :third]}
  end

  test "JSON import selects the trusted Plugin and preserves the same DSL data", %{jido: jido} do
    definition = Agent.definition()
    registry = Agent.registry()
    assert {:ok, document} = Jido.Test.AgentServer.Registry.encode(definition, registry)
    assert {:ok, imported} = Jido.Test.AgentServer.Registry.decode_json(Jason.encode!(document), registry)
    assert imported == definition
    {:ok, server} = Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, imported, id: unique_id())
    {:ok, signal} = Agent.add_signal(%{amount: 1})
    assert {:ok, %{state: %{count: 1, reached: [:first]}}, []} = Server.call(server, signal)

    assert {:error, _} =
             Jido.Test.AgentServer.Registry.decode_json(Jason.encode!(document), Catalog.new!([]))
  end

  test "map authors use the same validation as DSL authors" do
    definition = Agent.definition()
    [contribution] = definition.plugins
    raw = Map.from_struct(definition)
    assert {:ok, ^definition} = CoreAgent.define(raw)
    bad = put_in(contribution.data.thresholds, [%{name: :first, at: 0}])
    assert {:error, _} = CoreAgent.define(%{raw | plugins: [bad]})
    missing = put_in(contribution.data.on, "examples.plugins.dsl.missing")
    assert {:error, _} = CoreAgent.define(%{raw | plugins: [missing]})

    duplicate =
      put_in(contribution.data.thresholds, [%{name: :first, at: 1}, %{name: :first, at: 3}])

    assert {:error, _} = CoreAgent.define(%{raw | plugins: [duplicate]})
    assert {:error, _} = CoreAgent.define(%{raw | plugins: [%{contribution | vsn: 99}]})
  end
end
