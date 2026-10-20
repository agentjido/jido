Code.require_file("../support.ex", __DIR__)

defmodule JidoTest.AgentServer.Composition.RacesTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server.composition", async: false
  import JidoTest.Eventually
  alias Jido.AgentServer, as: Server
  alias JidoTest.AgentServer.Fixtures, as: F
  @moduletag capture_log: true

  defmodule DeliveryGate do
    use GenServer
    def start_link(observer), do: GenServer.start_link(__MODULE__, observer)
    def init(observer), do: {:ok, observer}

    def handle_call({:signal, _}, from, observer) do
      send(observer, {:orphan_delivery, from})
      {:noreply, observer}
    end
  end

  setup do
    F.setup_runtime()
  end

  defp agent(id), do: %{F.agent() | id: id}

  @tag obligation: "jido.agent_server.composition.I4"
  test "failed worker lookup stops the new activation and releases the child tag", c do
    schedulers = :erlang.system_flag(:schedulers_online, 1)
    on_exit(fn -> :erlang.system_flag(:schedulers_online, schedulers) end)
    {:ok, parent} = Server.start(agent: agent("lookup-parent"), jido: c.jido)
    {:ok, owned} = Server.Supervisor.child_supervisor(Server.activation(parent))

    for {placement, failure} <- [
          {:instance, :missing_worker},
          {:instance, :dead_root},
          {:owned, :missing_worker},
          {:independent, :missing_worker}
        ] do
      start = fn ->
        child = agent("lookup-#{placement}-#{failure}")

        if placement == :instance,
          do: Server.start(agent: child, jido: c.jido),
          else: Server.spawn_child(parent, child, :retry, placement: placement)
      end

      caller = Task.async(fn -> receive do: (:go -> start.()) end)
      observer = self()

      supervisor =
        if placement == :owned,
          do: owned,
          else: Process.whereis(Jido.agent_supervisor_name(c.jido))

      # Hold the caller before it receives the root. Tracing worker/1 itself is
      # too late: its which_children reply can already be in the caller mailbox.
      tracer =
        spawn_link(fn ->
          Process.flag(:priority, :max)
          send(observer, :lookup_tracer_ready)
          hold_worker_lookup(observer, caller.pid)
        end)

      assert_receive :lookup_tracer_ready, 1_000
      :erlang.trace(supervisor, true, [:send, {:tracer, tracer}])

      try do
        send(caller.pid, :go)
        assert_receive {:lookup_held, root}, 1_000

        case failure do
          :missing_worker ->
            :ok = Supervisor.terminate_child(root, Server)
            assert Process.alive?(root)

          :dead_root ->
            :ok = Supervisor.stop(root)
        end

        send(tracer, :resume)
        assert Task.await(caller) == {:error, :worker_unavailable}
        F.down(root)
        assert Server.children(parent) == %{}
      after
        :erlang.trace(supervisor, false, [:send])
        Process.unlink(tracer)
        Process.exit(tracer, :kill)
        Task.shutdown(caller, :brutal_kill)
      end

      assert {:ok, replacement} = start.()
      assert Server.await_ready(replacement) == :ok
      assert Server.stop(replacement) == :ok
    end

    assert Server.stop(parent) == :ok
    assert DynamicSupervisor.which_children(Jido.agent_supervisor_name(c.jido)) == []
  end

  defp hold_worker_lookup(observer, caller) do
    receive do
      {:trace, _supervisor, :send, {_tag, {:ok, root}}, _destination} when is_pid(root) ->
        true = :erlang.suspend_process(caller)
        send(observer, {:lookup_held, root})
        receive do: (:resume -> :erlang.resume_process(caller))
    end
  end

  @tag obligation: ["jido.agent_server.composition.I2", "jido.agent_server.composition.I3"]
  test "pending orphan delivery rejects adoption and keeps its deadline", c do
    sink = start_supervised!({DeliveryGate, self()})

    {:ok, parent} =
      Server.start(agent: agent("first-parent"), jido: c.jido, directive_timeout: 500)

    {:ok, adopter} = Server.start(agent: agent("adopter"), jido: c.jido)

    {:ok, orphan} =
      Server.spawn_child(parent, agent("orphan"), :orphan,
        placement: :independent,
        on_parent_exit: :emit_orphan,
        orphan_dispatch: {:pid, target: sink, delivery_mode: :sync}
      )

    root = Server.activation(orphan)
    assert Server.stop(parent) == :ok
    assert_receive {:orphan_delivery, {task, _}}, 1_000

    assert Server.adopt_child(adopter, orphan, :adopted) ==
             {:error, :orphan_dispatch_pending}

    assert Server.children(adopter) == %{}
    F.down(root)
    F.down(task)
    refute Process.alive?(orphan)
    assert {:ok, _} = Server.spawn_child(adopter, agent("reused"), :adopted)
  end

  @tag obligation: "jido.agent_server.composition.I3"
  test "adoption can resume after the orphan delivery completes", c do
    sink = start_supervised!({DeliveryGate, self()})
    {:ok, parent} = Server.start(agent: agent("first-parent"), jido: c.jido)
    {:ok, adopter} = Server.start(agent: agent("adopter"), jido: c.jido)

    {:ok, orphan} =
      Server.spawn_child(parent, agent("orphan"), :orphan,
        placement: :independent,
        on_parent_exit: :emit_orphan,
        orphan_dispatch: {:pid, target: sink, delivery_mode: :sync}
      )

    assert Server.stop(parent) == :ok
    assert_receive {:orphan_delivery, {task, _} = from}, 1_000
    GenServer.reply(from, :ok)
    F.down(task)
    assert_eventually(match?({_, %{parent_effect: nil}}, :sys.get_state(orphan)))
    assert Server.adopt_child(adopter, orphan, :adopted) == :ok
    assert Server.children(adopter).adopted.pid == orphan
  end

  @tag obligation: "jido.agent_server.composition.I3"
  test "ancestor failure during adoption rejects an uncertain relationship", c do
    {:ok, first} = Server.start(agent: agent("first"), jido: c.jido)

    {:ok, middle} =
      Server.spawn_child(first, agent("middle"), :middle,
        placement: :independent,
        on_parent_exit: :continue
      )

    {:ok, last} =
      Server.spawn_child(middle, agent("last"), :last,
        placement: :independent,
        on_parent_exit: :continue
      )

    first_root = Server.activation(first)
    middle_root = Server.activation(middle)
    :ok = :sys.suspend(middle)

    try do
      adoption = Task.async(fn -> Server.adopt_child(last, first, :first) end)

      assert_eventually(
        Enum.any?(elem(Process.info(middle, :messages), 1), fn
          {:"$gen_call", _, :parent} -> true
          _ -> false
        end)
      )

      Process.exit(middle, :kill)
      F.down(middle)
      assert Task.await(adoption) == {:error, :ancestor_unavailable}

      assert_eventually(
        match?(pid when is_pid(pid) and pid != middle, Server.whereis(c.jido, "middle"))
      )

      replacement = Server.whereis(c.jido, "middle")
      assert Server.status(first).parent == nil
      assert Server.status(replacement).parent.activation == first_root
      assert Server.status(last).parent.activation == middle_root
      assert Server.adopt_child(last, first, :first) == {:error, :cyclic_parent}
    after
      if Process.alive?(middle), do: :sys.resume(middle)
    end
  end

  @tag obligation: ["jido.agent_server.composition.I3", "jido.agent_server.composition.I4"]
  test "adoption rejects a bare worker before changing ownership", c do
    {:ok, parent} = Server.start(agent: agent("parent"), jido: c.jido)

    bare =
      start_supervised!(%{
        id: :bare,
        start: {Server, :start_link, [[agent: agent("bare"), jido: c.jido]]}
      })

    assert Server.activation(bare) == nil
    assert Server.adopt_child(parent, bare, :bare) == {:error, :activation_required}
    assert Server.alive?(bare)
    assert Server.agent(bare).id == "bare"
    assert Server.children(parent) == %{}
    assert {:ok, _} = Server.spawn_child(parent, agent("valid"), :bare)
  end

  @tag obligation: ["jido.agent_server.composition.I3", "jido.agent_server.composition.I4"]
  test "whole root replacement removes lost adoption and permits tag reuse", c do
    {:ok, parent} = Server.start(agent: agent("parent"), jido: c.jido)
    {:ok, adopted} = Server.start(agent: agent("adopted"), jido: c.jido)
    assert Server.adopt_child(parent, adopted, :adopted) == :ok
    root = Server.activation(adopted)
    Process.exit(root, :kill)
    F.down(root)

    assert_eventually(
      match?(pid when is_pid(pid) and pid != adopted, Server.whereis(c.jido, "adopted"))
    )

    replacement = Server.whereis(c.jido, "adopted")
    assert Server.activation(replacement) != root
    assert Server.status(replacement).parent == nil
    assert Server.children(parent) == %{}
    assert Server.stop_child(parent, :adopted) == {:error, :child_not_found}

    assert_eventually(
      match?(
        {_, %{child_monitors: monitors}} when map_size(monitors) == 0,
        :sys.get_state(parent)
      )
    )

    assert {:ok, next} = Server.spawn_child(parent, agent("next"), :adopted)
    assert Server.children(parent).adopted.pid == next
  end
end
