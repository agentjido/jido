Code.require_file("application_supervision.ex", __DIR__)

defmodule Jido.Examples.ApplicationSupervisionTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.ApplicationSupervision

  test "the host supervisor owns the Jido instance and installed Agent" do
    suffix = System.unique_integer([:positive])
    host = :"example_host_#{suffix}"
    instance = :"example_host_jido_#{suffix}"

    host_pid =
      start_supervised!(
        {ApplicationSupervision,
         name: host, instance: instance, namespace: "examples/application-supervision/#{suffix}"},
        id: host
      )

    server = await_agent(instance, "installed-agent", 100)
    assert is_pid(server)
    assert Jido.AgentServer.snapshot(server).agent.state.ready

    host_monitor = Process.monitor(host_pid)
    server_monitor = Process.monitor(server)
    assert :ok = stop_supervised(host)
    assert_receive {:DOWN, ^host_monitor, :process, ^host_pid, _reason}, 1_000
    assert_receive {:DOWN, ^server_monitor, :process, ^server, _reason}, 1_000
    refute Process.whereis(instance)
  end

  defp await_agent(_instance, _id, 0), do: nil

  defp await_agent(instance, id, attempts) do
    case Jido.whereis_agent(instance, id) do
      pid when is_pid(pid) ->
        pid

      nil ->
        receive do
        after
          10 -> await_agent(instance, id, attempts - 1)
        end
    end
  end
end
