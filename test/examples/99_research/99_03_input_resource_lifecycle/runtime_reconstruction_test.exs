defmodule JidoTest.Examples.RuntimeReconstructionTest do
  use JidoTest.Case, async: true
  @moduletag :example
  alias Jido.Examples.RuntimeReconstruction, as: Example
  alias Example.Runtime
  alias Jido.AgentServer, as: Server

  setup %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, Example, id: unique_id("feed"))
    runtime = plugin_runtime(server)
    init = Runtime.inspect_runtime(runtime).init
    eventually(fn -> Runtime.inspect_runtime(runtime).feed == "A" end)
    %{server: server, runtime: runtime, init: init}
  end

  test "saved state rebuilds the feed through immutable bootstrap state", c do
    assert Map.get(c.init, :plugin_state) == %{name: "A"}
    assert Map.get(c.init, :state_version) == 0

    old_resource = Runtime.inspect_runtime(c.runtime).resource
    resource_ref = Process.monitor(old_resource)
    assert {:ok, _} = Example.select(c.server, "B")
    assert_receive {:DOWN, ^resource_ref, :process, ^old_resource, _}, 1_000
    current_resource = Runtime.inspect_runtime(c.runtime).resource
    current_ref = Process.monitor(current_resource)
    Process.exit(c.runtime, :kill)
    assert_receive {:DOWN, ^current_ref, :process, ^current_resource, _}, 1_000

    replacement =
      eventually(fn -> plugin_runtime(c.server) != c.runtime && plugin_runtime(c.server) end)

    assert replacement != c.runtime
    eventually(fn -> Runtime.inspect_runtime(replacement).feed == "B" end)
    assert {:error, :stale_feed} = Runtime.input(replacement, "A", "old")
    assert :ok = Runtime.input(replacement, "B", "new")
    eventually(fn -> Jido.AgentServer.snapshot(c.server).agent.state.items == ["new"] end)
    resource = Runtime.inspect_runtime(replacement).resource
    ref = Process.monitor(resource)
    assert :ok = Jido.AgentServer.stop(c.server)
    assert_receive {:DOWN, ^ref, :process, ^resource, _}, 1_000
  end

  test "replacement Init supplies committed owned state and its version", c do
    assert {:ok, _} = Example.select(c.server, "B")
    version = Jido.AgentServer.snapshot(c.server).state_version
    Process.exit(c.runtime, :kill)

    replacement =
      eventually(fn -> plugin_runtime(c.server) != c.runtime && plugin_runtime(c.server) end)

    init = Runtime.inspect_runtime(replacement).init
    assert Map.get(init, :plugin_state) == %{name: "B"}
    assert Map.get(init, :state_version) == version
  end

  defp plugin_runtime(server) do
    case Server.children(server)[{:plugin, Example.Plugin}] do
      %{pid: pid} when is_pid(pid) -> pid
      _child -> nil
    end
  end
end
