defmodule JidoTest.Examples.Plugins.LivePluginChangesTest do
  use JidoTest.Case, async: true
  @moduletag :example
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.LivePluginChanges, as: Example
  alias Example.{Cache, CacheRuntime}
  import JidoTest.AgentServerAssertions, only: [plugin: 2]

  test "live changes replace the runtime and removal requires an owned-state decision", %{
    jido: jido
  } do
    {:ok, server} = JidoTest.ExampleRuntime.start_agent(jido, Example, id: unique_id())
    assert {:ok, install} = Example.install_signal()
    assert {:ok, _, _} = Server.call(server, install)
    assert :ok = Server.await_ready(server)
    first = plugin(server, Cache).pid
    assert %{capacity: 2, value: 5, revision: 1, notifications: 0} = CacheRuntime.snapshot(first)

    before = Server.snapshot(server)
    assert {:ok, invalid} = Example.configure_signal(%{capacity: 0})
    assert {:error, _} = Server.call(server, invalid)
    assert Server.snapshot(server) == before
    assert plugin(server, Cache).pid == first
    refute CacheRuntime.snapshot(first).paused

    monitor = Process.monitor(first)
    assert {:ok, configure} = Example.configure_signal(%{capacity: 4})
    assert {:ok, _, _} = Server.call(server, configure)
    assert :ok = Server.await_ready(server)
    assert_receive {:DOWN, ^monitor, :process, ^first, _}, 5_000
    second = plugin(server, Cache).pid
    assert second != first

    assert %{capacity: 4, value: 5, revision: 2, paused: false, notifications: 0} =
             CacheRuntime.snapshot(second)

    assert {:ok, refresh} = Example.refresh_signal()

    for _ <- 1..5 do
      assert {:ok, _, []} = Server.call(server, refresh)
    end

    eventually(fn -> CacheRuntime.snapshot(second).notifications == 5 end)

    assert %{entries: [{7, 5}, {6, 5}, {5, 5}, {4, 5}], revision: 7} =
             CacheRuntime.snapshot(second)

    assert {:ok, keep} = Example.remove_signal(%{discard: false})
    assert {:error, _} = Server.call(server, keep)
    assert Server.snapshot(server).state_version == 7
    assert plugin(server, Cache).pid == second
    monitor = Process.monitor(second)
    assert {:ok, remove} = Example.remove_signal(%{discard: true})
    assert {:ok, agent, _} = Server.call(server, remove)
    assert :ok = Server.await_ready(server)
    assert_receive {:DOWN, ^monitor, :process, ^second, _}, 5_000
    refute Map.has_key?(agent.state, :cache)
    assert plugin(server, Cache) == nil
    assert :ok = Jido.stop_agent(jido, server)
  end
end
