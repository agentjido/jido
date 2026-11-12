defmodule Jido.Agent.StateBoundaryTest do
  use Jido.Test.Case, async: true

  alias Jido.Agent
  alias Jido.AgentServer

  defmodule Replace do
    use Jido.Action,
      name: "state_boundary_replace"

    def run(%{candidate: candidate}, _context) do
      signal = Jido.Signal.new!("state.invalid", %{}, source: "/test")
      {:ok, candidate, [Jido.Agent.Directive.emit(signal)]}
    end
  end

  test "invalid complete state cannot commit or run its effects", %{jido: jido} do
    schema =
      Jido.Joi.object(%{
        nested: Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(1)}) |> Jido.Joi.default(%{})
      })

    definition =
      Agent.define!(%{
        name: "state_boundary",
        schema: schema,
        routes: [
          %{
            path: "state.replace",
            handler: %{kind: :action, target: Replace},
            state: %{source: :output, path: []}
          }
        ]
      })

    agent = Agent.instantiate!(definition, id: unique_id("defaults"))
    {:ok, server} = Jido.Test.AgentServer.Assertions.start_agent(jido, agent)
    before = Jido.Test.AgentServer.Assertions.committed(server)

    for candidate <- [
          %{},
          %{nested: %{}},
          %{nested: nil},
          %{nested: %{count: nil}},
          %{nested: %{count: "bad"}}
        ] do
      input = signal("state.replace", %{candidate: candidate})
      assert {:error, %{__exception__: true}} = Agent.cmd(agent, input)

      assert {:ok, %Jido.AgentServer.TurnResult{status: :failed}} =
               AgentServer.call(server, input)

      assert Jido.Test.AgentServer.Assertions.committed(server) === before
      assert Agent.validate(agent) === {:ok, agent}
    end
  end

  defmodule Keep do
    use Jido.Action,
      name: "state_boundary_keep"

    def run(_params, context), do: {:ok, context.agent_state}
  end

  defmodule OwnedState do
    use Jido.Plugin
    @impl true
    def state_spec(_opts),
      do:
        {:owned,
         Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.nullable() |> Jido.Joi.default(3)})
         |> Jido.Joi.default(%{})}

    @impl true
    def reduce(reduction, _opts), do: {:ok, reduction.signal.data.owned}
  end

  test "Plugin reductions validate stored output without defaults", %{jido: jido} do
    definition =
      Agent.define!(%{
        name: "owned_defaults",
        plugins: [
          %{id: OwnedState.id(), provider: OwnedState, vsn: OwnedState.vsn(), data: %{}}
        ],
        routes: [
          %{
            path: "owned.reduce",
            handler: %{kind: :action, target: Keep},
            state: %{source: :output, path: []}
          }
        ]
      })

    agent = Agent.instantiate!(definition, id: unique_id("owned-defaults"))
    {:ok, server} = Jido.Test.AgentServer.Assertions.start_agent(jido, agent)
    before = Jido.Test.AgentServer.Assertions.committed(server)

    for owned <- [%{}, nil, %{count: "bad"}] do
      input = signal("owned.reduce", %{owned: owned})
      assert {:error, _} = Agent.cmd(agent, input)

      assert {:ok, %Jido.AgentServer.TurnResult{status: :failed}} =
               AgentServer.call(server, input)

      assert Jido.Test.AgentServer.Assertions.committed(server) === before
    end

    input = signal("owned.reduce", %{owned: %{count: nil}})
    assert {:ok, direct, []} = Agent.cmd(agent, input)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             AgentServer.call(server, input)

    live = AgentServer.snapshot(server).agent
    assert direct.state.owned === %{count: nil}
    assert live.state === direct.state
    assert Agent.validate(live) === {:ok, live}
  end
end
