defmodule JidoTest.Examples.RuntimeReconstructionTest do
  use JidoTest.Case, async: true
  @moduletag :example
  alias Jido.Examples.RuntimeReconstruction, as: Example
  alias Example.Runtime

  setup %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, Example.new_for(self()), id: "feed")
    assert_receive {:feed_runtime, runtime, init}, 1_000
    eventually(fn -> Runtime.inspect_runtime(runtime).feed == "A" end)
    %{server: server, runtime: runtime, init: init}
  end

  test "saved state rebuilds the feed through the existing public pull API", c do
    old_resource = Runtime.inspect_runtime(c.runtime).resource
    resource_ref = Process.monitor(old_resource)
    assert {:ok, _} = Example.select(c.server, "B")
    assert_receive {:DOWN, ^resource_ref, :process, ^old_resource, _}, 1_000
    current_resource = Runtime.inspect_runtime(c.runtime).resource
    current_ref = Process.monitor(current_resource)
    Process.exit(c.runtime, :kill)
    assert_receive {:DOWN, ^current_ref, :process, ^current_resource, _}, 1_000
    assert_receive {:feed_runtime, replacement, _init}, 1_000
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
    assert_receive {:feed_runtime, _replacement, init}, 1_000
    assert Map.get(init, :plugin_state) == %{name: "B"}
    assert Map.get(init, :state_version) == version
  end
end
