defmodule JidoTest.Examples.MultiAgent.AgentHierarchyTest do
  use JidoTest.FeatureSDKCase
  @moduletag group: :multi_agent
  alias Jido.Examples.AgentHierarchy

  defp tree(jido) do
    root = start_agent!(jido, AgentHierarchy)
    assert {:ok, _} = AgentHierarchy.grow(root, 2)
    eventually(fn -> length(descendants(root)) == 6 end)
    {root, descendants(root)}
  end

  defp descendants(server) do
    Enum.flat_map(Server.children(server), fn {_, child} ->
      [child | descendants(child.pid)]
    end)
  end

  test "a two-level tree has six real descendants with direct parent bindings", %{jido: jido} do
    {root, nodes} = tree(jido)
    assert map_size(Server.children(root)) == 2
    assert length(Enum.uniq_by(nodes, & &1.id)) == 6

    for {_, child} <- Server.children(root) do
      assert Server.status(child.pid).runtime.parent.pid == root
      assert map_size(Server.children(child.pid)) == 2

      for {_, leaf} <- Server.children(child.pid) do
        assert Server.status(leaf.pid).runtime.parent.pid == child.pid
        assert Server.children(leaf.pid) == %{}
      end
    end
  end

  test "a branch crash stops its descendants and preserves its sibling", %{jido: jido} do
    {root, _} = tree(jido)
    left = Server.children(root)["left"]
    right = Server.children(root)["right"]

    monitors =
      Enum.map(descendants(left.pid), fn child -> {child.pid, Process.monitor(child.pid)} end)

    Process.exit(left.pid, :kill)
    for {pid, ref} <- monitors, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 1_000)
    eventually(fn -> state(root).lost_children == ["left"] end)
    assert Process.alive?(right.pid)
    assert map_size(Server.children(right.pid)) == 2
    assert Server.children(root)["right"].pid == right.pid
  end

  test "root shutdown removes every descendant from the instance registry", %{jido: jido} do
    {root, nodes} = tree(jido)
    monitors = Enum.map(nodes, fn child -> {child.pid, Process.monitor(child.pid)} end)
    assert :ok = Jido.stop_agent(jido, root)
    for {pid, ref} <- monitors, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 1_000)
    eventually(fn -> Enum.all?(nodes, &(Jido.whereis_agent(jido, &1.id) == nil)) end)
  end

  test "depth bounds reject work before a commit or child creation", %{jido: jido} do
    root = start_agent!(jido, AgentHierarchy, error_policy: :log_only)

    for depth <- [-1, 5] do
      assert {:error, _} = AgentHierarchy.grow(root, depth)
      assert Server.snapshot(root).state_version == 0
      assert Server.children(root) == %{}
    end

    assert {:ok, _} = AgentHierarchy.grow(root, 0)
    assert {:error, _} = AgentHierarchy.grow(root, 0)
  end
end
