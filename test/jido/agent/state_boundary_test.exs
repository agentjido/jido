defmodule Jido.Agent.StateBoundaryTest do
  use JidoTest.Case, async: true

  alias Jido.Agent
  alias Jido.AgentServer

  defmodule Replace do
    use Jido.Action, name: "state_boundary_replace"

    def run(%{candidate: candidate}, _context),
      do: {:ok, candidate, [Jido.Agent.Directive.stop(:invalid_state_committed)]}
  end

  test "invalid complete state cannot commit or run its effects", %{jido: jido} do
    schema =
      Zoi.object(%{
        nested: Zoi.object(%{count: Zoi.integer() |> Zoi.default(1)}) |> Zoi.default(%{})
      })

    definition =
      Agent.new!(name: "state_boundary", schema: schema, routes: [{"state.replace", Replace}])

    agent = Agent.instantiate!(definition, id: unique_id("defaults"))
    {:ok, server} = Jido.start_agent(jido, agent)
    before = AgentServer.snapshot(server)

    for candidate <- [
          %{},
          %{nested: %{}},
          %{nested: nil},
          %{nested: %{count: nil}},
          %{nested: %{count: "bad"}}
        ] do
      input = signal("state.replace", %{candidate: candidate})
      assert {:error, %Jido.Error.ValidationError{}} = Agent.cmd(agent, input)
      assert {:error, %Jido.Error.ValidationError{}} = AgentServer.call(server, input)
      assert AgentServer.snapshot(server) === before
      assert Agent.validate_instance(agent) === {:ok, agent}
    end
  end

  defmodule Keep do
    use Jido.Action, name: "state_boundary_keep"
    def run(_params, context), do: {:ok, context.agent_state}
  end

  defmodule OwnedState do
    use Jido.Plugin
    @impl true
    def state_spec(_opts),
      do:
        {:owned,
         Zoi.object(%{count: Zoi.integer() |> Zoi.nullable() |> Zoi.default(3)})
         |> Zoi.default(%{})}

    @impl true
    def reduce(reduction, _opts), do: {:ok, reduction.signal.data.owned}
  end

  test "Plugin reductions validate stored output without defaults", %{jido: jido} do
    definition =
      Agent.new!(name: "owned_defaults", plugins: [OwnedState], routes: [{"owned.reduce", Keep}])

    agent = Agent.instantiate!(definition, id: unique_id("owned-defaults"))
    {:ok, server} = Jido.start_agent(jido, agent)
    before = AgentServer.snapshot(server)

    for owned <- [%{}, nil, %{count: "bad"}] do
      input = signal("owned.reduce", %{owned: owned})
      assert {:error, _} = Agent.cmd(agent, input)
      assert {:error, _} = AgentServer.call(server, input)
      assert AgentServer.snapshot(server) === before
    end

    input = signal("owned.reduce", %{owned: %{count: nil}})
    assert {:ok, direct, []} = Agent.cmd(agent, input)
    assert {:ok, live} = AgentServer.call(server, input)
    assert direct.state.owned === %{count: nil}
    assert live.state === direct.state
    assert Agent.validate_instance(live) === {:ok, live}
  end
end
