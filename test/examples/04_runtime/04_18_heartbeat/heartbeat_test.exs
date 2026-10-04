defmodule JidoTest.Examples.Runtime.HeartbeatTest do
  use JidoTest.Case, async: false

  @moduletag :example

  alias Jido.Agent
  alias Jido.AgentServer
  alias Jido.Examples.Heartbeat.{CustomAgent, DefaultAgent}
  alias Jido.Plugin.Heartbeat

  test "explicit ticks deliver the default and custom Signals", %{jido: jido} do
    {:ok, default_server} =
      Jido.start_agent(jido, DefaultAgent, id: unique_id("heartbeat-default"))

    default_runtime = runtime(default_server)
    send(default_runtime, :tick)

    eventually(fn ->
      AgentServer.agent(default_server).state.events == [
        %{
          type: "jido.agent.heartbeat",
          source: "/plugin/heartbeat",
          data: %{kind: "default"}
        }
      ]
    end)

    {:ok, custom_server} =
      Jido.start_agent(jido, CustomAgent, id: unique_id("heartbeat-custom"))

    custom_runtime = runtime(custom_server)
    send(custom_runtime, :tick)

    eventually(fn ->
      AgentServer.agent(custom_server).state.events == [
        %{
          type: "examples.runtime.heartbeat.custom",
          source: "/examples/runtime/heartbeat",
          data: %{kind: "custom"}
        }
      ]
    end)
  end

  test "invalid options fail before an Agent or runtime starts" do
    assert {:error, %Jido.Error.ValidationError{} = error} =
             Agent.new(
               name: "runtime_heartbeat_invalid",
               schema: Zoi.object(%{}),
               plugins: [{Heartbeat, [interval: 0]}]
             )

    assert error.message == "Heartbeat Plugin options are invalid"
    assert error.details.reason == {:invalid_heartbeat_interval, 0}
  end

  test "the owner replaces a failed runtime and stops the replacement", %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, DefaultAgent, id: unique_id("heartbeat-lifecycle"))
    old_runtime = runtime(server)
    old_monitor = Process.monitor(old_runtime)

    Process.exit(old_runtime, :kill)
    assert_receive {:DOWN, ^old_monitor, :process, ^old_runtime, :killed}, 1_000

    new_runtime =
      eventually(fn ->
        case runtime(server) do
          pid when is_pid(pid) and pid != old_runtime -> pid
          _pid -> false
        end
      end)

    send(new_runtime, :tick)
    eventually(fn -> length(AgentServer.agent(server).state.events) == 1 end)

    cleanup_monitor = Process.monitor(new_runtime)
    assert :ok = Jido.stop_agent(jido, server)
    assert_receive {:DOWN, ^cleanup_monitor, :process, ^new_runtime, _reason}, 1_000
  end

  defp runtime(server) do
    AgentServer.children(server)
    |> Map.fetch!({:plugin, Heartbeat})
    |> Map.fetch!(:pid)
  end
end
