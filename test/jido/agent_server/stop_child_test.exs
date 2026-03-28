defmodule JidoTest.AgentServer.StopChildTest do
  use JidoTest.Case, async: false

  alias Jido.AgentServer

  defmodule ParentAgent do
    @moduledoc false
    use Jido.Agent, name: "stop_child_parent_agent", schema: []
  end

  defmodule ChildAgent do
    @moduledoc false
    use Jido.Agent, name: "stop_child_child_agent", schema: []
  end

  test "stop_child/3 stops an adopted child with an atom tag", %{jido: jido} do
    {:ok, parent_pid} = AgentServer.start(agent: ParentAgent, id: unique_id("parent"), jido: jido)
    {:ok, child_pid} = AgentServer.start(agent: ChildAgent, id: unique_id("child"), jido: jido)

    assert {:ok, ^child_pid} = AgentServer.adopt_child(parent_pid, child_pid, :worker)
    assert :ok = AgentServer.stop_child(parent_pid, :worker)

    eventually(fn -> not Process.alive?(child_pid) end)
    eventually_state(parent_pid, fn state -> map_size(state.children) == 0 end)
  end

  test "stop_child/3 stops an adopted child with a string tag", %{jido: jido} do
    {:ok, parent_pid} = AgentServer.start(agent: ParentAgent, id: unique_id("parent"), jido: jido)
    {:ok, child_pid} = AgentServer.start(agent: ChildAgent, id: unique_id("child"), jido: jido)

    assert {:ok, ^child_pid} = AgentServer.adopt_child(parent_pid, child_pid, "worker")
    assert :ok = AgentServer.stop_child(parent_pid, "worker")

    eventually(fn -> not Process.alive?(child_pid) end)
    eventually_state(parent_pid, fn state -> map_size(state.children) == 0 end)
  end
end
