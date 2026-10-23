Code.require_file("../support.ex", __DIR__)

defmodule JidoTest.AgentServer.Composition.ChildrenTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server.composition", async: false
  import JidoTest.Eventually
  alias Jido.AgentServer, as: Server
  alias JidoTest.AgentServer.Fixtures, as: F
  @moduletag capture_log: true

  defmodule Resource do
    use GenServer
    def start_link(init), do: GenServer.start_link(__MODULE__, init)

    def init(init) do
      if init.options[:observer], do: send(init.options[:observer], {:resource, self(), init})
      {:ok, init}
    end

    def handle_call(:owner, _, init), do: {:reply, init.agent_server, init}
  end

  defmodule DeliveryGate do
    use GenServer
    def start_link(observer), do: GenServer.start_link(__MODULE__, observer)
    def init(observer), do: {:ok, observer}

    def handle_call({:signal, _}, from, observer) do
      send(observer, {:orphan_delivery, self(), from})
      {:noreply, observer}
    end
  end

  defmodule WorkerPlugin do
    use Jido.Plugin

    def child_spec(init),
      do: %{id: __MODULE__, start: {Resource, :start_link, [init]}, shutdown: 50}

    def await_ready(root, opts) do
      if opts[:gate] do
        send(opts[:observer], {:ready_gate, self(), root})
        receive do: (:release -> :ok)
      else
        :ok
      end
    end
  end

  defmodule Tree do
    use Supervisor
    def start_link(init), do: Supervisor.start_link(__MODULE__, init)

    def init(init),
      do:
        Supervisor.init([%{id: :leaf, start: {Resource, :start_link, [init]}}],
          strategy: :one_for_one
        )
  end

  defmodule TreePlugin do
    use Jido.Plugin

    def child_spec(init),
      do: %{id: __MODULE__, start: {Tree, :start_link, [init]}, type: :supervisor}
  end

  setup do
    name = Module.concat(__MODULE__, "Observer#{System.unique_integer([:positive])}")
    Process.register(self(), name)
    Map.put(F.setup_runtime(), :observer, name)
  end

  defp agent(id, plugins \\ []) do
    Jido.Agent.define!(%{
      name: "activation_contract",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
      extensions:
        Enum.map(
          plugins,
          fn declaration ->
            {provider, options} =
              case declaration do
                {provider, options} -> {provider, options}
                provider -> {provider, []}
              end

            %{id: provider.id(), provider: provider, vsn: provider.vsn(), data: Map.new(options)}
          end
        ),
      routes: [
        %{
          path: "work",
          handler: %{kind: :action, target: F.Work},
          state: %{source: :output, path: []}
        }
      ]
    })
    |> Jido.Agent.instantiate!(id: id)
  end

  defp root(server), do: Server.activation(server)
  defp child(root, id), do: root |> Supervisor.which_children() |> List.keyfind(id, 0) |> elem(1)

  @tag obligation: "jido.agent_server.composition.I1"
  test "owned children and nested Plugin trees stop with the complete parent activation", c do
    parent = F.start(%{c | agent: agent("parent")})

    {:ok, first} =
      Server.spawn_child(parent, agent("owned", [{TreePlugin, observer: c.observer}]), :first)

    {:ok, second} = Server.spawn_child(parent, agent("sibling"), :second)
    {:ok, grandchild} = Server.spawn_child(first, agent("grandchild"), :grandchild)
    assert Server.await_ready(first) == :ok
    children = Server.children(parent)
    assert children.first.pid == first
    assert children.first.placement == :owned
    owned_supervisor = child(root(parent), :owned_agents)

    assert Enum.any?(
             DynamicSupervisor.which_children(owned_supervisor),
             &(elem(&1, 1) == root(first))
           )

    plugin = child(root(first), {:plugin, TreePlugin})
    leaf = child(plugin, :leaf)

    resources = [
      parent,
      root(parent),
      first,
      root(first),
      second,
      root(second),
      grandchild,
      root(grandchild),
      plugin,
      leaf,
      owned_supervisor
    ]

    assert Server.stop(parent) == :ok
    for pid <- resources, do: refute(Process.alive?(pid))
    F.clean(c.runner)
  end

  @tag obligation: ["jido.agent_server.composition.I1", "jido.agent_server.composition.I4"]
  test "child restart refreshes inspection and a stopped tag can be reused", c do
    parent = F.start(%{c | agent: agent("parent")})
    {:ok, first} = Server.spawn_child(parent, agent("child"), :child)
    first_root = root(first)
    Process.exit(first, :kill)
    F.down(first)
    assert_eventually(Server.children(parent).child.pid != first)
    replacement = Server.children(parent).child.pid
    assert root(replacement) == first_root
    assert Server.stop_child(parent, :child) == :ok
    refute Process.alive?(first_root)
    assert_eventually(Server.children(parent) == %{})
    {:ok, next} = Server.spawn_child(parent, agent("next"), :child)
    assert Server.children(parent).child.pid == next
    assert {:error, :child_not_found} = Server.stop_child(parent, :missing)
  end

  @tag obligation: "jido.agent_server.composition.I2"
  test "independent children keep their Plugins after parent shutdown", c do
    {:ok, parent} = Server.start(agent: agent("parent"), jido: c.jido)

    {:ok, independent} =
      Server.spawn_child(
        parent,
        agent("independent", [{TreePlugin, observer: c.observer}]),
        :independent,
        placement: :independent,
        on_parent_exit: :continue
      )

    assert Server.await_ready(independent) == :ok
    independent_root = root(independent)
    plugin = child(independent_root, {:plugin, TreePlugin})
    leaf = child(plugin, :leaf)

    assert Enum.any?(
             DynamicSupervisor.which_children(Jido.agent_supervisor_name(c.jido)),
             &(elem(&1, 1) == independent_root)
           )

    assert Server.stop(parent) == :ok
    assert_eventually(Server.status(independent).parent == nil)
    for pid <- [independent, independent_root, plugin, leaf], do: assert(Process.alive?(pid))
    assert {:ok, _, []} = Server.call(independent, F.signal())
    assert Server.stop(independent) == :ok
    for pid <- [independent, independent_root, plugin, leaf], do: refute(Process.alive?(pid))
  end

  @tag obligation: ["jido.agent_server.composition.I2", "jido.agent_server.composition.I3"]
  test "parent stop, orphan Signal, and adoption use activation lifetime", c do
    {:ok, parent} = Server.start(agent: agent("parent"), jido: c.jido)

    {:ok, stop_child} =
      Server.spawn_child(parent, agent("stop-child"), :stops, placement: :independent)

    stop_root = root(stop_child)

    {:ok, orphan} =
      Server.spawn_child(parent, agent("orphan"), :orphan,
        placement: :independent,
        on_parent_exit: :emit_orphan,
        orphan_dispatch: {:pid, target: self()}
      )

    assert Server.stop(parent) == :ok
    F.down(stop_root)

    assert_receive {:signal,
                    %{
                      type: "jido.agent_server.orphaned",
                      data: %{parent_id: "parent", tag: :orphan}
                    }},
                   1_000

    assert Server.status(orphan).parent == nil
    Process.exit(orphan, :kill)
    F.down(orphan)
    assert_eventually(is_pid(Server.whereis(c.jido, "orphan")))
    orphan = Server.whereis(c.jido, "orphan")
    assert Server.await_ready(orphan) == :ok
    assert_eventually(match?({_, %{parent: nil, parent_effect: nil}}, :sys.get_state(orphan)))
    refute_received {:signal, %{type: "jido.agent_server.orphaned"}}
    {:ok, adopter} = Server.start(agent: agent("adopter"), jido: c.jido)
    assert Server.adopt_child(adopter, orphan, :adopted) == :ok
    adopter_root = root(adopter)
    orphan_root = root(orphan)
    Process.exit(adopter, :kill)
    F.down(adopter)
    assert_eventually(is_pid(Server.whereis(c.jido, "adopter")))
    adopter = Server.whereis(c.jido, "adopter")
    assert Server.children(adopter).adopted.pid == orphan
    assert Server.status(orphan).parent.activation == adopter_root
    Process.exit(orphan, :kill)
    F.down(orphan)
    assert_eventually(is_pid(Server.whereis(c.jido, "orphan")))
    orphan = Server.whereis(c.jido, "orphan")
    assert Server.status(orphan).parent.activation == adopter_root
    assert Server.stop(adopter) == :ok
    F.down(orphan_root)
  end

  @tag obligation: "jido.agent_server.composition.I4"
  test "invalid lifetimes, duplicate tags, and failed starts leave no child ownership", c do
    parent = F.start(%{c | agent: agent("parent")})

    for {opts, reason} <- [
          {[placement: :wrong], :invalid_placement},
          {[on_parent_exit: :continue], :owned_child_cannot_survive_parent},
          {[on_parent_exit: :wrong], :invalid_parent_policy},
          {[restart: :wrong], :invalid_restart_policy},
          {[server_options: %{}], :invalid_child_options},
          {[server_options: [jido: c.jido]], :invalid_child_options},
          {[server_options: [agent: agent("ignored")]], :invalid_child_options},
          {[server_options: [name: :ignored]], :invalid_child_options},
          {[server_options: [turn_timeout: 1, turn_timeout: 2]], :invalid_child_options},
          {[server_options: [unknown: true]], :invalid_child_options},
          {[meta: :not_a_map], :invalid_child_options},
          {[meta: %URI{}], :invalid_child_options},
          {[typo: true], :invalid_child_options},
          {[placement: :owned, placement: :independent], :invalid_child_options}
        ] do
      assert {:error, ^reason} = Server.spawn_child(parent, agent("bad"), :bad, opts)
    end

    assert {:error, :invalid_child_options} =
             Server.spawn_child(parent, agent("bad"), :bad, :not_options)

    for tag <- [nil, 1, []] do
      assert {:error, :invalid_child_tag} = Server.spawn_child(parent, agent("bad"), tag)
    end

    assert {:error, :jido_instance_required} =
             Server.spawn_child(parent, agent("no-instance"), :bad, placement: :independent)

    assert Server.children(parent) == %{}
    assert {:error, _} = Server.spawn_child(parent, :invalid, :bad)
    {:ok, first} = Server.spawn_child(parent, agent("first"), :tag)
    assert {:error, :tag_in_use} = Server.spawn_child(parent, agent("other"), :tag)
    assert Server.children(parent).tag.pid == first
    {:ok, instance_parent} = Server.start(agent: agent("registered-parent"), jido: c.jido)

    assert {:error, _} =
             Server.spawn_child(instance_parent, agent("registered-parent"), :collision)

    {:ok, valid} = Server.spawn_child(instance_parent, agent("valid"), :collision)
    assert Server.children(instance_parent).collision.pid == valid

    assert {:error, :invalid_orphan_dispatch} =
             Server.spawn_child(instance_parent, agent("bad-policy"), :bad,
               placement: :independent,
               on_parent_exit: :emit_orphan
             )

    {:ok, metadata_child} =
      Server.spawn_child(instance_parent, agent("metadata"), :metadata,
        placement: :independent,
        on_parent_exit: :continue,
        meta: %{source: :contract}
      )

    assert Server.status(metadata_child).parent.meta == %{source: :contract}
  end

  @tag obligation: "jido.agent_server.composition.I3"
  test "adoption rejects live parents, cross-instance children, self-adoption, and cycles", c do
    {:ok, parent} = Server.start(agent: agent("parent"), jido: c.jido)
    {:ok, other} = Server.start(agent: agent("other"), jido: c.jido)

    {:ok, attached} =
      Server.spawn_child(parent, agent("attached"), :attached, placement: :independent)

    assert Server.adopt_child(other, attached, :taken) == {:error, :already_attached}
    assert Server.adopt_child(parent, parent, :self) == {:error, :self_adoption}
    assert Server.adopt_child(attached, parent, :cycle) == {:error, :cyclic_parent}
    other_instance = Module.concat(__MODULE__, "Other#{System.unique_integer([:positive])}")
    start_supervised!({Jido, name: other_instance})
    {:ok, foreign} = Server.start(agent: agent("foreign"), jido: other_instance)
    assert Server.adopt_child(parent, foreign, :foreign) == {:error, :different_instance}
    assert Server.children(other) == %{}
    assert Server.adopt_child(parent, self(), :invalid) == {:error, :invalid_child_options}

    assert Server.adopt_child(parent, attached, :invalid, :not_options) ==
             {:error, :invalid_child_options}

    assert Server.adopt_child(parent, attached, :invalid, placement: :owned) ==
             {:error, :invalid_child_options}

    assert Server.adopt_child(parent, attached, :invalid, server_options: [turn_timeout: 1]) ==
             {:error, :invalid_child_options}

    dead = spawn(fn -> :ok end)
    F.down(dead)
    assert Server.adopt_child(parent, dead, :dead) == {:error, :invalid_child_options}
  end

  @tag obligation: ["jido.agent_server.composition.I1", "jido.agent_server.composition.I4"]
  test "whole child root replacement refreshes the tracked activation", c do
    parent = F.start(%{c | agent: agent("parent")})
    {:ok, worker} = Server.spawn_child(parent, agent("child"), :child)
    old_root = root(worker)
    Process.exit(old_root, :kill)
    F.down(old_root)

    assert_eventually(
      match?(%{child: %{activation: next}} when next != old_root, Server.children(parent))
    )

    replacement = Server.children(parent).child
    assert Server.agent(replacement.pid).id == "child"
    assert Server.stop_child(parent, :child) == :ok
    refute Process.alive?(replacement.activation)
  end

  @tag obligation: "jido.agent_server.composition.I4"
  test "concurrent callers cannot claim the same tag", c do
    parent = F.start(%{c | agent: agent("parent")})

    attempts =
      for i <- 1..2 do
        Task.async(fn -> Server.spawn_child(parent, agent("child-#{i}"), :child) end)
      end

    results = Enum.map(attempts, &Task.await/1)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert {:error, :tag_in_use} in results
    assert map_size(Server.children(parent)) == 1
  end

  @tag obligation: "jido.agent_server.composition.I1"
  test "bare workers cannot own child activations", c do
    assert {:ok, worker} = Server.start_link(agent: agent("bare"), runner: c.runner)
    assert Server.activation(worker) == nil
    assert {:error, :activation_required} = Server.spawn_child(worker, agent("child"), :child)
    assert Server.children(worker) == %{}
    assert :ok = Server.stop(worker, :normal)
  end

  @tag obligation: "jido.agent_server.composition.I4"
  test "failed child operations release caller monitors as well as tag reservations", c do
    {:ok, parent} = Server.start(agent: agent("parent"), jido: c.jido)
    {:monitors, baseline} = Process.info(parent, :monitors)

    for _ <- 1..20 do
      assert {:error, _} = Server.spawn_child(parent, agent("parent"), :failed)
    end

    assert Server.children(parent) == %{}
    assert_eventually(length(elem(Process.info(parent, :monitors), 1)) == length(baseline))
    assert {:ok, _} = Server.spawn_child(parent, agent("valid"), :failed)
  end

  @tag obligation: "jido.agent_server.composition.I3"
  test "concurrent adoption cannot create a parent cycle", c do
    for i <- 1..5 do
      {:ok, a} = Server.start(agent: agent("cycle-a-#{i}"), jido: c.jido)
      {:ok, b} = Server.start(agent: agent("cycle-b-#{i}"), jido: c.jido)

      calls =
        for {parent, child} <- [{a, b}, {b, a}] do
          Task.async(fn ->
            receive do: (:go -> Server.adopt_child(parent, child, :peer))
          end)
        end

      for task <- calls, do: send(task.pid, :go)
      results = Enum.map(calls, &Task.await/1)
      assert Enum.count(results, &(&1 == :ok)) == 1
      assert Enum.any?(results, &(&1 in [{:error, :cyclic_parent}, {:error, :adoption_busy}]))
      parent = if hd(results) == :ok, do: a, else: b
      descendant = if parent == a, do: b, else: a
      descendant_root = root(descendant)
      assert :ok = Server.stop(parent)
      F.down(descendant_root)
    end
  end

  @tag obligation: "jido.agent_server.composition.I4"
  test "a dead startup caller cannot attach an old child after its tag is reused", c do
    {:ok, parent} = Server.start(agent: agent("parent"), jido: c.jido)
    guard = Process.whereis(Jido.registration_guard_name(c.jido))
    :sys.suspend(guard)
    on_exit(fn -> if Process.alive?(guard), do: :sys.resume(guard) end)
    abandoned = Task.async(fn -> Server.spawn_child(parent, agent("abandoned"), :retry) end)

    assert_eventually(
      Enum.any?(elem(Process.info(guard, :messages), 1), fn
        {:"$gen_call", _, {:claim, {:agent, "abandoned"}, _, _}} -> true
        _ -> false
      end)
    )

    Task.shutdown(abandoned, :brutal_kill)
    # Private capability only controls the startup race; results use public APIs.
    %{state: table} = :gen_statem.call(parent, :child_context)
    assert_eventually(:ets.lookup(table, {:child, :retry}) == [])
    retry_task = Task.async(fn -> Server.spawn_child(parent, agent("replacement"), :retry) end)

    assert_eventually(
      match?(
        [{_, %{caller: pid}}] when pid == retry_task.pid,
        :ets.lookup(table, {:child, :retry})
      )
    )

    :sys.resume(guard)
    assert {:ok, replacement} = Task.await(retry_task)
    assert Server.children(parent).retry.pid == replacement
    assert Server.whereis(c.jido, "abandoned") == nil
    owned = child(root(parent), :owned_agents)
    assert length(DynamicSupervisor.which_children(owned)) == 1
    assert Server.stop_child(parent, :retry) == :ok
  end

  @tag obligation: "jido.agent_server.composition.I4"
  test "direct child stop also releases its parent tag and root monitor", c do
    parent = F.start(%{c | agent: agent("parent")})
    {:monitors, before} = Process.info(parent, :monitors)
    {:ok, worker} = Server.spawn_child(parent, agent("child"), :child)
    assert Server.stop(worker) == :ok
    assert_eventually(length(elem(Process.info(parent, :monitors), 1)) == length(before))
    assert {:ok, _} = Server.spawn_child(parent, agent("replacement"), :child)
  end

  @tag obligation: "jido.agent_server.composition.I3"
  test "orphan dispatch failure or timeout stops its owned task and activation", c do
    for mode <- [:failure, :timeout] do
      sink = start_supervised!(Supervisor.child_spec({DeliveryGate, self()}, id: make_ref()))
      if mode == :failure, do: GenServer.stop(sink)

      {:ok, parent} =
        Server.start(agent: agent("parent-#{mode}"), jido: c.jido, directive_timeout: 75)

      {:ok, orphan} =
        Server.spawn_child(
          parent,
          agent("orphan-#{mode}", [{TreePlugin, observer: c.observer}]),
          :orphan,
          placement: :independent,
          on_parent_exit: :emit_orphan,
          orphan_dispatch: {:pid, target: sink, delivery_mode: :sync}
        )

      assert Server.await_ready(orphan) == :ok
      orphan_root = root(orphan)
      resource = child(orphan_root, {:plugin, TreePlugin})
      assert Server.stop(parent) == :ok

      if mode == :timeout do
        assert_receive {:orphan_delivery, ^sink, {task, _}}, 1_000
        F.down(task)
        assert Process.alive?(sink)
      end

      F.down(orphan_root)
      refute Process.alive?(resource)
    end
  end

  @tag obligation: "jido.agent_server.composition.I3"
  test "a queued orphan dispatch result cannot bypass its actual deadline", c do
    sink = start_supervised!({DeliveryGate, self()})
    {:ok, parent} = Server.start(agent: agent("parent"), jido: c.jido, directive_timeout: 150)

    {:ok, orphan} =
      Server.spawn_child(parent, agent("orphan"), :orphan,
        placement: :independent,
        on_parent_exit: :emit_orphan,
        orphan_dispatch: {:pid, target: sink, delivery_mode: :sync}
      )

    orphan_root = root(orphan)
    assert Server.stop(parent) == :ok
    assert_receive {:orphan_delivery, ^sink, {task, _} = from}, 1_000
    :sys.suspend(orphan)
    on_exit(fn -> if Process.alive?(orphan), do: :sys.resume(orphan) end)
    GenServer.reply(from, :ok)
    F.down(task)
    F.elapsed(170)
    :sys.resume(orphan)
    F.down(orphan_root)
    assert Process.alive?(sink)
  end
end
