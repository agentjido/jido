Code.require_file("heartbeat.ex", __DIR__)

defmodule Jido.Examples.Runtime.HeartbeatTest do
  use Jido.Test.Case, async: false
  @moduletag :integration

  alias Jido.Agent
  alias Jido.Examples.Heartbeat.{CustomAgent, DefaultAgent}
  alias Jido.Plugin.Timer

  test "static Timer intervals deliver the default and custom Signals", %{jido: jido} do
    {:ok, default_server} =
      Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, DefaultAgent, id: unique_id("heartbeat-default"))

    eventually(fn ->
      case Jido.AgentServer.snapshot(default_server).agent.state.events do
        [%{type: "jido.agent.heartbeat", source: "/plugin/heartbeat", data: %{kind: "default"}} | _rest] ->
          true

        _events ->
          false
      end
    end)

    {:ok, custom_server} =
      Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, CustomAgent, id: unique_id("heartbeat-custom"))

    eventually(fn ->
      case Jido.AgentServer.snapshot(custom_server).agent.state.events do
        [
          %{
            type: "examples.runtime.heartbeat.custom",
            source: "/examples/runtime/heartbeat",
            data: %{kind: "custom"}
          }
          | _rest
        ] ->
          true

        _events ->
          false
      end
    end)
  end

  test "invalid options fail before an Agent or runtime starts" do
    assert {:error, %Jido.Error.ValidationError{} = error} =
             Agent.define(%{
               name: "runtime_heartbeat_invalid",
               schema: Jido.Joi.object(%{}),
               plugins: [
                 %{
                   id: Timer.id(),
                   provider: Timer,
                   vsn: Timer.vsn(),
                   data: %{interval: 0}
                 }
               ]
             })

    assert error.message == "Timer static interval options are invalid"
    assert error.details.reason == {:invalid_timer_interval, 0}
  end

  test "the owner replaces a failed runtime and stops the replacement", %{jido: jido} do
    {:ok, server} =
      Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, DefaultAgent, id: unique_id("heartbeat-lifecycle"))

    activation = Jido.Test.AgentServer.ExampleRuntime.activation(server)
    old_runtime = runtime(server)
    old_monitor = Process.monitor(old_runtime)

    Process.exit(old_runtime, :kill)
    assert_receive {:DOWN, ^old_monitor, :process, ^old_runtime, :killed}, 1_000

    new_runtime =
      eventually(fn ->
        case Jido.Test.AgentServer.ExampleRuntime.plugin(activation, Timer) do
          pid when is_pid(pid) and pid != old_runtime -> pid
          _pid -> false
        end
      end)

    server = Jido.AgentServer.Supervisor.worker(activation)
    assert :ok = Jido.AgentServer.await_ready(server)
    eventually(fn -> Jido.AgentServer.snapshot(server).agent.state.events != [] end)

    cleanup_monitor = Process.monitor(new_runtime)
    assert :ok = Jido.stop_agent(jido, server)
    assert_receive {:DOWN, ^cleanup_monitor, :process, ^new_runtime, _reason}, 1_000
  end

  defp runtime(server) do
    Jido.Test.AgentServer.ExampleRuntime.plugin(Jido.Test.AgentServer.ExampleRuntime.activation(server), Timer)
  end
end
