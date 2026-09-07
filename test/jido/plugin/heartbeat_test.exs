defmodule Jido.Plugin.HeartbeatTest do
  use JidoTest.Case, async: false

  alias Jido.AgentServer, as: Server
  alias Jido.Plugin
  alias Jido.Plugin.{Heartbeat, Init}

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

  test "rejects invalid options before runtime startup" do
    for {opts, reason} <- [
          {[interval: 0], {:invalid_heartbeat_interval, 0}},
          {[interval: -1], {:invalid_heartbeat_interval, -1}},
          {[interval: 1.0], {:invalid_heartbeat_interval, 1.0}},
          {[signal_type: ""], {:invalid_heartbeat_signal_type, ""}},
          {[signal_type: 42], {:invalid_heartbeat_signal_type, 42}},
          {[signal_type: <<255>>], {:invalid_heartbeat_signal_type, <<255>>}},
          {[signal_data: []], {:invalid_heartbeat_signal_data, []}},
          {[signal_data: %URI{}], {:invalid_heartbeat_signal_data, %URI{}}},
          {[source: ""], {:invalid_heartbeat_source, ""}},
          {[source: 42], {:invalid_heartbeat_source, 42}},
          {[source: "not a URI reference"], {:invalid_heartbeat_source, "not a URI reference"}}
        ] do
      assert {:error, %Jido.Error.ValidationError{} = error} =
               Plugin.normalize_all([{Heartbeat, opts}])

      assert error.message == "Heartbeat Plugin options are invalid"
      assert error.details.reason == reason

      init = %Init{
        agent_server: self(),
        agent_id: "agent",
        module: Heartbeat,
        options: opts
      }

      assert {:error, ^reason} = Heartbeat.Runtime.start_link(init)
    end

    invalid_options = %{}

    assert {:error, {:invalid_heartbeat_options, ^invalid_options}} =
             Heartbeat.configuration(invalid_options)

    init = %Init{
      agent_server: self(),
      agent_id: "agent",
      module: Heartbeat,
      options: invalid_options
    }

    assert {:error, {:invalid_heartbeat_options, ^invalid_options}} =
             Heartbeat.Runtime.start_link(init)
  end
end
