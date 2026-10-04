defmodule JidoTest.Examples.MultiAgent.OrphanAdoptionTest do
  use JidoTest.Case, async: false

  @moduletag :example

  alias Jido.AgentServer
  alias Jido.Examples.OrphanAdoption.Parent

  test "the continue policy leaves a live unattached child", %{jido: jido} do
    {:ok, parent} = Jido.start_agent(jido, Parent, id: unique_id("continue-parent"))
    child = spawn_child(parent, :continue)
    child_pid = child.pid
    child_monitor = Process.monitor(child_pid)

    assert :ok = Jido.stop_agent(jido, parent)

    eventually(fn -> AgentServer.status(child_pid).runtime.parent == nil end)
    assert Process.alive?(child_pid)
    assert AgentServer.agent(child_pid).state.orphans == []

    assert :ok = Jido.stop_agent(jido, child_pid)
    assert_receive {:DOWN, ^child_monitor, :process, ^child_pid, _reason}, 1_000
  end

  test "an orphan-emitting child can be adopted and addressed by a new parent", %{jido: jido} do
    {:ok, former_parent} =
      Jido.start_agent(jido, Parent, id: unique_id("orphan-former-parent"))

    former_parent_id = AgentServer.agent(former_parent).id
    child = spawn_child(former_parent, :emit_orphan)
    assert :ok = Jido.stop_agent(jido, former_parent)

    eventually(fn ->
      AgentServer.agent(child.pid).state.orphans == [
        %{
          parent_id: former_parent_id,
          tag: :worker,
          meta: %{policy: :emit_orphan},
          reason: :shutdown
        }
      ]
    end)

    {:ok, adopter} = Jido.start_agent(jido, Parent, id: unique_id("orphan-adopter"))
    adopter_id = AgentServer.agent(adopter).id

    assert :ok = AgentServer.adopt_child(adopter, child.pid, :adopted, %{role: :worker})

    assert %{pid: child_pid, id: child_id, meta: %{role: :worker}} =
             AgentServer.children(adopter).adopted

    assert child_pid == child.pid
    assert child_id == child.id
    assert AgentServer.status(child.pid).runtime.parent.id == adopter_id

    assert {:error, {:child_tag_in_use, :adopted}} =
             AgentServer.adopt_child(adopter, child.pid, :adopted)

    assert {:error, {:adopt_child_failed, :child_not_found}} =
             AgentServer.adopt_child(adopter, "missing-child", :missing)

    {:ok, forward} = Parent.forward_signal(%{value: 7})
    assert {:ok, parent_after_forward} = AgentServer.call(adopter, forward)
    assert parent_after_forward.state.forwarded == 1
    eventually(fn -> AgentServer.agent(child.pid).state.total == 7 end)

    child_monitor = Process.monitor(child_pid)
    assert :ok = AgentServer.stop_child(adopter, :adopted)
    assert_receive {:DOWN, ^child_monitor, :process, ^child_pid, _reason}, 1_000
    assert :ok = Jido.stop_agent(jido, adopter)
    eventually(fn -> Jido.whereis_agent(jido, child.id) == nil end)
  end

  defp spawn_child(parent, policy) do
    {:ok, signal} = Parent.spawn_signal(%{policy: policy})
    assert {:ok, _agent} = AgentServer.call(parent, signal)
    eventually(fn -> Map.get(AgentServer.children(parent), :worker) end)
  end
end
