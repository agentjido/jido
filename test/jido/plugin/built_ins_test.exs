defmodule Jido.Plugin.BuiltInsTest do
  use JidoTest.Case, async: false

  alias Jido.AgentServer, as: Server
  alias Jido.Plugin.Heartbeat
  alias Jido.Signal

  defmodule Spend do
    @schema Zoi.struct(__MODULE__, %{amount: Zoi.integer() |> Zoi.min(1)})
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    def schema, do: @schema
  end

  defmodule Credits do
    use Jido.Plugin

    @impl Jido.Plugin
    def state_spec(_opts), do: {:credits, Zoi.integer() |> Zoi.min(0) |> Zoi.default(3)}

    @impl Jido.Plugin
    def directives(_opts), do: [Spend]

    @impl Jido.Plugin
    def validate_directive(%Spend{} = directive, _opts),
      do: Zoi.parse(Spend.schema(), directive)

    @impl Jido.Plugin
    def update_state(credits, directives, _opts),
      do:
        {:ok,
         Enum.reduce(directives, credits, fn %Spend{amount: amount}, left -> left - amount end)}
  end

  defmodule SpendCredits do
    use Jido.Action, name: "plugin_spend_credits"

    @impl Jido.Action
    def run(%{amount: amount}, context) do
      {:ok, context.agent_state, [%Spend{amount: amount}]}
    end
  end

  defmodule RecordHeartbeat do
    use Jido.Action, name: "plugin_record_heartbeat"

    @impl Jido.Action
    def run(params, context) do
      {:ok, %{context.agent_state | heartbeats: context.agent_state.heartbeats ++ [params]}}
    end
  end

  defmodule DataAgent do
    use Jido.Agent,
      name: "plugin_data_agent",
      routes: [{"plugin.credits.spend", SpendCredits}],
      plugins: [Credits]
  end

  defmodule HeartbeatAgent do
    use Jido.Agent,
      name: "plugin_heartbeat_agent",
      schema: Zoi.object(%{heartbeats: Zoi.list(Zoi.any()) |> Zoi.default([])}),
      routes: [{"plugin.heartbeat", RecordHeartbeat}],
      plugins: [
        {Heartbeat,
         interval: 10, signal_type: "plugin.heartbeat", signal_data: %{source: :plugin}}
      ]
  end

  test "state-only Plugins compose optional state into the Agent" do
    agent = DataAgent.new!()

    assert agent.state == %{credits: 3}
    assert agent.schema.fields == []
    assert Keyword.keys(Jido.Agent.complete_schema!(agent).fields) == [:credits]
  end

  test "state-only Plugin Directives update state without a Plugin runtime", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, DataAgent, id: unique_id("plugin-data"))

    signal = Signal.new!("plugin.credits.spend", %{amount: 1}, source: "/test")

    assert {:ok, agent} = Server.call(pid, signal)
    assert agent.state.credits == 2
    assert Server.children(pid) == %{}
  end

  test "a runtime-only Plugin can feed Signals into its Agent", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, HeartbeatAgent, id: unique_id("heartbeat"))

    eventually(fn ->
      case Server.agent(pid).state.heartbeats do
        [%{source: :plugin} | _rest] -> true
        _heartbeats -> false
      end
    end)

    assert %{
             {:plugin, Heartbeat} => %{
               kind: :plugin,
               module: Heartbeat,
               pid: runtime_pid
             }
           } = Server.children(pid)

    assert is_pid(runtime_pid)
  end
end
