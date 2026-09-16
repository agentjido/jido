defmodule JidoTest.Agent.ReplacementTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.Signal

  defmodule Reset do
    use Jido.Action, name: "agent_replacement_reset"

    def run(_params, context), do: {:ok, %{context.agent_state | config: %{}}}
  end

  defmodule Configured do
    use Jido.Agent,
      name: "agent_replacement_configured",
      schema: Zoi.object(%{config: Zoi.map() |> Zoi.default(%{})}),
      routes: [{"config.reset", Reset}]
  end

  test "set deep-merges while a complete Action candidate replaces a domain field", %{jido: jido} do
    initial = Configured.new!(id: unique_id("config-reset"), state: %{config: %{a: 1}})

    assert {:ok, merged} = Jido.Agent.set(initial, config: %{})
    assert merged.state.config == %{a: 1}

    signal = Signal.new!("config.reset", %{}, source: "/test")
    assert {:ok, direct, []} = Configured.cmd(initial, signal)
    assert direct.state.config == %{}
    assert initial.state.config == %{a: 1}

    assert {:ok, server} = Jido.start_agent(jido, initial)
    assert {:ok, live} = Server.call(server, signal)
    assert live.state == direct.state
    assert Server.snapshot(server).state_version == 1
  end
end
