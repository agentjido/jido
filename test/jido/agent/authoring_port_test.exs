defmodule Jido.Agent.AuthoringPortTest do
  use JidoTest.Case, async: true
  alias Jido.Agent
  alias Jido.AgentServer

  defmodule Leaf do
    use Jido.Agent, name: "authoring_port_leaf"

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      signal_source "/authoring-port"

      route "counter.increment", as: :increment do
        action %{amount: amount}, context: context do
          {:ok, %{context.agent_state | count: context.agent_state.count + amount}}
        end
      end

      route "counter.invalid" do
        action _input do
          {:ok, %{count: "invalid"}}
        end
      end
    end
  end

  test "Map and DSL values run the same local Action Turn" do
    definition = Leaf.definition()
    from_map = Agent.define!(Map.from_struct(definition))
    signal = Leaf.increment_signal(%{amount: 2}) |> elem(1)
    expected = %{definition | id: "leaf", state: %{count: 2}}

    for source <- [Leaf, definition, from_map] do
      instance = Agent.instantiate!(source, id: "leaf")
      assert {:ok, ^expected, []} = Agent.cmd(instance, signal)
      assert instance.state == %{count: 0}
      assert Agent.definition(expected) === definition
    end
  end

  test "a leaf activation retains the definition and commits only valid complete state", %{
    jido: jido
  } do
    instance = Leaf.instantiate!(id: unique_id("port"))
    assert {:ok, server} = Jido.start_agent(jido, instance)
    assert :ok = AgentServer.await_ready(server)
    assert {:ok, signal} = Leaf.increment_signal(%{amount: 3})
    assert {:ok, updated, []} = AgentServer.call(server, signal)
    assert updated.state == %{count: 3}
    assert Agent.definition(updated) === Leaf.definition()
    invalid = Jido.Signal.new!("counter.invalid", %{}, source: "/test")
    assert {:error, _} = AgentServer.call(server, invalid)
    assert AgentServer.agent(server) === updated
    assert AgentServer.status(server).state_version == 1
  end
end
