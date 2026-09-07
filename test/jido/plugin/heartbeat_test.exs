defmodule Jido.Plugin.HeartbeatTest do
  use JidoTest.Case, async: false

  alias Jido.AgentServer, as: Server
  alias Jido.Plugin.Heartbeat

  defmodule RecordHeartbeat do
    use Jido.Action, name: "plugin_record_heartbeat"

    @impl Jido.Action
    def run(params, context) do
      {:ok, %{context.agent_state | heartbeats: context.agent_state.heartbeats ++ [params]}}
    end
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
