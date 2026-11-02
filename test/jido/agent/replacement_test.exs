defmodule JidoTest.Agent.ReplacementTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.Signal

  defmodule Reset do
    use Jido.Action,
      name: "agent_replacement_reset"

    def run(_params, context), do: {:ok, %{context.agent_state | config: %{}}}
  end

  defmodule Configured do
    use Jido.Agent, name: "agent_replacement_configured"

    state do
      schema Zoi.object(%{config: Zoi.map() |> Zoi.default(%{})})
    end

    routes do
      route "config.reset", Reset
    end
  end

  test "set and complete Action candidates replace a domain field", %{jido: jido} do
    initial = Configured.instantiate!(id: unique_id("config-reset"), state: %{config: %{a: 1}})

    assert {:ok, updated} = Jido.Agent.set(initial, config: %{})
    assert updated.state.config == %{}

    signal = Signal.new!("config.reset", %{}, source: "/test")
    assert {:ok, direct, []} = Configured.cmd(initial, signal)
    assert direct.state.config == %{}
    assert updated.state == direct.state
    assert initial.state.config == %{a: 1}

    assert {:ok, server} = JidoTest.AgentServerAssertions.start_agent(jido, initial)
    assert {:ok, live, _} = Server.call(server, signal)
    assert live.state == direct.state
    assert Server.status(server).state_version == 1
  end
end
