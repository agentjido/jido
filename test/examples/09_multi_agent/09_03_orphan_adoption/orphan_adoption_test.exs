Code.require_file("../../support/loader.exs", __DIR__)

alias JidoTest.Examples.Loader
Loader.require_source!("09_multi_agent/support/worker.ex")
Loader.require_source!("09_multi_agent/09_03_orphan_adoption/orphan_adoption.ex")

defmodule JidoTest.Examples.MultiAgent.OrphanAdoptionTest do
  use Jido.Test.Case, async: false
  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!("09_multi_agent/09_03_orphan_adoption/orphan_adoption.ex")
    :ok
  end

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.OrphanAdoption.Parent

  test "the continue policy leaves a live unattached worker", %{jido: jido} do
    {:ok, parent} =
      Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, Parent, id: unique_id("continue-parent"))

    assert {:ok, worker} = Parent.start_worker(parent, :continue)
    monitor = Process.monitor(worker)
    assert :ok = Jido.stop_agent(jido, parent)
    eventually(fn -> Server.status(worker).parent == nil end)
    assert Server.agent(worker).state.total == 0
    assert :ok = Jido.stop_agent(jido, worker)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
  end

  test "an orphan notification precedes adoption by a new owner", %{jido: jido} do
    {:ok, parent} =
      Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, Parent, id: unique_id("former-parent"))

    parent_id = Server.agent(parent).id

    assert {:ok, worker} =
             Parent.start_worker(parent, :emit_orphan, orphan_dispatch: {:pid, target: self()})

    worker_id = Server.agent(worker).id
    assert :ok = Jido.stop_agent(jido, parent)

    assert_receive {:signal,
                    %{
                      type: "jido.agent_server.orphaned",
                      data: %{parent_id: ^parent_id, tag: :worker}
                    }},
                   1_000

    eventually(fn -> Server.status(worker).parent == nil end)

    {:ok, adopter} = Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, Parent, id: unique_id("adopter"))
    assert :ok = Server.adopt_child(adopter, worker, :adopted)
    assert %{pid: ^worker, placement: :independent} = Server.children(adopter).adopted
    assert Server.status(worker).parent.agent_id == Server.agent(adopter).id
    assert {:error, _} = Server.adopt_child(adopter, worker, :adopted)
    assert {:error, _} = Server.adopt_child(adopter, "missing-worker", :missing)

    {:ok, signal} = Parent.forward_signal(%{value: 7})
    assert {:ok, %{state: %{forwarded: 1}}, [_]} = Server.call(adopter, signal)
    eventually(fn -> Server.agent(worker).state.total == 7 end)
    monitor = Process.monitor(worker)
    assert :ok = Server.stop_child(adopter, :adopted)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
    assert Jido.whereis_agent(jido, worker_id) == nil
    assert :ok = Jido.stop_agent(jido, adopter)
  end
end
