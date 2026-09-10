defmodule Jido.Plugin.PreparationTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server

  defmodule PrepareFacet do
    use Jido.Agent.Plugin

    alias Jido.Agent.Plugin.Preparation

    @impl true
    def prepare(%Preparation{} = preparation, opts) do
      case Keyword.get(opts, :mode, :ok) do
        :ok ->
          {:ok,
           %{
             agent_id: preparation.agent_id,
             signal_id: preparation.signal.id,
             signal_type: preparation.signal.type
           }}

        :reject ->
          {:error, :denied}

        :invalid ->
          :invalid

        :non_portable ->
          {:ok, self()}
      end
    end
  end

  defmodule Package do
    use Jido.Plugin, agent: Jido.Plugin.PreparationTest.PrepareFacet
  end

  defmodule Capture do
    use Jido.Action,
      name: "plugin_preparation_capture",
      schema: Zoi.object(%{value: Zoi.integer()})

    alias Jido.Plugin.PreparationTest.Package

    @impl true
    def run(%{value: value}, context) do
      prepared = Map.fetch!(context.plugin_inputs, Package)

      {:ok,
       %{
         context.agent_state
         | action_signal_id: context.signal.id,
           prepared_agent_id: prepared.agent_id,
           prepared_signal_id: prepared.signal_id,
           prepared_signal_type: prepared.signal_type,
           value: value
       }}
    end
  end

  test "direct cmd provides one package-owned input without changing the Signal" do
    agent = agent(:ok)
    source = signal("prepare.run", %{value: 7})

    assert {:ok, next, []} = Jido.Agent.cmd(agent, source)
    assert next.state.value == 7
    assert next.state.action_signal_id == source.id
    assert next.state.prepared_signal_id == source.id
    assert next.state.prepared_signal_type == source.type
    assert next.state.prepared_agent_id == agent.id
  end

  test "live execution uses the same pure preparation", %{jido: jido} do
    agent = agent(:ok)
    source = signal("prepare.run", %{value: 8})
    {:ok, server} = Jido.start_agent(jido, agent)

    assert {:ok, next} = Server.call(server, source)
    assert next.state.value == 8
    assert next.state.action_signal_id == source.id
    assert next.state.prepared_signal_id == source.id
    assert next.state.prepared_agent_id == agent.id
  end

  test "prepare can reject but cannot return a non-portable or invalid input" do
    source = signal("prepare.run", %{value: 1})

    assert {:error, :denied} = Jido.Agent.cmd(agent(:reject), source)

    assert {:error, invalid} = Jido.Agent.cmd(agent(:invalid), source)
    assert invalid.message == "Agent Plugin prepare/2 returned an invalid result"

    assert {:error, non_portable} = Jido.Agent.cmd(agent(:non_portable), source)
    assert non_portable.message == "Agent Plugin prepare/2 returned a non-portable input"
    assert non_portable.details.code == :non_portable_term
  end

  test "caller context cannot supply plugin inputs" do
    source = signal("prepare.run", %{value: 1})

    assert {:error, error} =
             Jido.Agent.cmd(agent(:ok), source, context: %{plugin_inputs: %{Package => :forged}})

    assert error.message == "Agent command context contains reserved keys"
    assert error.details.keys == [:plugin_inputs]
  end

  defp agent(mode) do
    Jido.Agent.new!(
      name: "plugin_preparation_agent",
      schema:
        Zoi.object(%{
          action_signal_id: Zoi.string() |> Zoi.default(""),
          prepared_agent_id: Zoi.string() |> Zoi.default(""),
          prepared_signal_id: Zoi.string() |> Zoi.default(""),
          prepared_signal_type: Zoi.string() |> Zoi.default(""),
          value: Zoi.integer() |> Zoi.default(0)
        }),
      routes: [{"prepare.run", Capture}],
      plugins: [{Package, mode: mode}]
    )
    |> Jido.Agent.instantiate!(id: unique_id("prepared"))
  end
end
