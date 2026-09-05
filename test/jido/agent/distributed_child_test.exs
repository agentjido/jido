defmodule JidoTest.Agent.DistributedChildTest do
  use JidoTest.PeerCase, async: false

  @moduletag capability: "DIST-01"

  alias Jido.AgentServer, as: Server
  alias Jido.Agent.Directive
  alias JidoTest.RemoteChildFixtures, as: Fixtures
  alias Jido.Examples.{RemoteCounter, RemoteParent}

  test "a generated command reaches an existing Agent on another node", context do
    %{jido: jido, peer_a: peer_a, peer_b: peer_b, node_b: node_b} = context

    assert {:ok, remote} =
             peer_call(peer_b, Jido, :start_agent, [jido, RemoteCounter, [id: "remote-counter"]])

    assert node(remote) == node_b

    assert Enum.any?(
             peer_call(peer_b, DynamicSupervisor, :which_children, [
               Jido.agent_supervisor_name(jido)
             ]),
             fn {_id, pid, _type, _modules} -> pid == remote end
           )

    # RPC only invokes the public command on A. The command itself must cross
    # the distribution connection from A to the Agent Server on B.
    assert {:ok, %{state: %{value: 7}}} =
             peer_call(peer_a, RemoteCounter, :record, [remote, 7])

    assert %{state_version: 1, agent: %{state: %{value: 7}}} =
             peer_call(peer_b, Server, :snapshot, [remote])

    assert :ok = peer_call(peer_b, Jido, :stop_agent, [jido, remote])

    eventually(fn ->
      peer_call(peer_b, Jido, :whereis_agent, [jido, "remote-counter"]) == nil
    end)
  end

  test "a parent places its owned child on the requested remote node", context do
    %{jido: jido, peer_a: peer_a, node_a: node_a, node_b: node_b} = context

    assert {:ok, parent} =
             peer_call(peer_a, Jido, :start_agent, [jido, RemoteParent, [id: "parent"]])

    assert node(parent) == node_a
    assert {:ok, _agent} = peer_call(peer_a, RemoteParent, :request_child, [parent, node_b])
    assert {:ok, _agent} = peer_call(peer_a, RemoteParent, :synchronize, [parent])

    child = eventually(fn -> peer_call(peer_a, Server, :children, [parent])[:worker] end)

    assert node(child.pid) == node_b
    assert peer_call(context.peer_b, Jido, :whereis_agent, [jido, child.id]) == child.pid
    assert peer_call(peer_a, Jido, :whereis_agent, [jido, child.id]) == nil

    assert %{runtime: %{parent: %{pid: ^parent, id: "parent", tag: :worker}}} =
             peer_call(context.peer_b, Server, :status, [child.pid])

    assert Enum.any?(supervised(context.peer_b, jido), fn {_, pid, _, _} -> pid == child.pid end)

    assert {:ok, _} = peer_call(peer_a, RemoteParent, :request_result, [parent, 9, "request-1"])

    eventually(fn ->
      peer_call(peer_a, Server, :agent, [parent]).state.result ==
        %{value: 9, request_id: "request-1", executed_on: node_b}
    end)

    assert peer_call(context.peer_b, Server, :snapshot, [child.pid]).state_version == 1
    assert :ok = peer_call(peer_a, Server, :stop_child, [parent, :worker])
    eventually(fn -> peer_call(context.peer_b, Jido, :whereis_agent, [jido, child.id]) == nil end)
    assert peer_call(peer_a, Server, :children, [parent]) == %{}
  end

  test "local default and explicit local placement keep the existing behavior", c do
    parent = start_parent(c)

    for {tag, opts} <- [{:default, []}, {:explicit, [node: c.node_a]}] do
      dispatch(c, parent, Directive.spawn_agent(RemoteCounter, tag, opts))
      child = child(c, parent, tag)
      assert node(child.pid) == c.node_a
      assert :ok = peer_call(c.peer_a, Server, :stop_child, [parent, tag])
    end
  end

  test "remote restart retains state and explicit stop removes a permanent child", c do
    parent = start_parent(c)
    directive = Directive.spawn_agent(RemoteCounter, :worker, node: c.node_b, restart: :permanent)
    dispatch(c, parent, directive)
    first = child(c, parent)
    assert {:ok, _} = peer_call(c.peer_a, RemoteCounter, :record, [first.pid, 11])
    peer_call(c.peer_b, Process, :exit, [first.pid, :kill])

    next =
      eventually(
        fn ->
          case peer_call(c.peer_a, Server, :children, [parent])[:worker] do
            %{pid: pid} = current when pid != first.pid -> current
            _ -> nil
          end
        end,
        timeout: 2_000
      )

    assert node(next.pid) == c.node_b
    assert next.id == first.id

    assert %{state_version: 1, agent: %{state: %{value: 11}}} =
             peer_call(c.peer_b, Server, :snapshot, [next.pid])

    assert :ok = peer_call(c.peer_a, Server, :stop_child, [parent, :worker])
    assert supervised(c.peer_b, c.jido) == []
    assert peer_call(c.peer_b, Jido, :whereis_agent, [c.jido, first.id]) == nil
  end

  test "parent shutdown and death stop remote work and its execution task", c do
    for reason <- [:shutdown, :kill] do
      parent = start_parent(c, id: "parent-#{reason}")
      # Permanent restart also must stop when this parent activation is gone.
      dispatch(
        c,
        parent,
        Directive.spawn_agent(Fixtures.Child, :worker, node: c.node_b, restart: :permanent)
      )

      worker = child(c, parent)
      observer = peer_call(c.peer_b, Fixtures, :observer, [])
      signal = Jido.Signal.new!("test.remote.hold", %{observer: observer}, source: "/test")
      dispatch(c, parent, Directive.emit_to_child(:worker, signal))
      task = eventually(fn -> peer_call(c.peer_b, Fixtures, :observed, [observer]) end)
      assert node(task) == c.node_b
      refute task == worker.pid
      assert %{phase: :running} = peer_call(c.peer_b, Server, :status, [worker.pid])

      if reason == :kill do
        peer_call(c.peer_a, Process, :exit, [parent, :kill])
      else
        assert :ok = peer_call(c.peer_a, Jido, :stop_agent, [c.jido, parent])
      end

      eventually(fn -> not peer_call(c.peer_b, Process, :alive?, [task]) end, timeout: 2_000)
      eventually(fn -> supervised(c.peer_b, c.jido) == [] end, timeout: 2_000)
      assert peer_call(c.peer_b, Jido, :whereis_agent, [c.jido, worker.id]) == nil

      eventually(fn ->
        peer_call(c.peer_b, Jido.RuntimeStore, :list, [c.jido, :agent_spawn_requests]) == []
      end)
    end
  end

  test "an unavailable node reports an uncertain outcome and never falls back locally", c do
    parent = start_parent(c)
    missing = :"jido_missing@127.0.0.1"
    dispatch(c, parent, Directive.spawn_agent(RemoteCounter, :worker, node: missing))

    assert {{:child_spawn_indeterminate, :worker, ^missing, request, :noconnection}, outcome} =
             failure(c)

    assert {generation, ref} = request
    assert is_integer(generation) and is_reference(ref)
    assert outcome.status == :indeterminate
    assert outcome.committed?
    assert peer_call(c.peer_a, Server, :children, [parent]) == %{}
    assert peer_call(c.peer_a, Jido, :whereis_agent, [c.jido, "parent/worker"]) == nil
  end

  test "a missing Agent module or Jido instance fails without a local child", c do
    peer_call(c.peer_a, Code, :compile_string, [
      "defmodule JidoTest.OnlyOriginAgent do use Jido.Agent, name: \"only_origin_agent\" end"
    ])

    parent = start_parent(c)
    dispatch(c, parent, Directive.spawn_agent(JidoTest.OnlyOriginAgent, :worker, node: c.node_b))
    assert {{:spawn_agent_failed, _}, %{status: :failed}} = failure(c)
    assert supervised(c.peer_b, c.jido) == []
    assert peer_call(c.peer_a, Server, :children, [parent]) == %{}
    assert :ok = peer_call(c.peer_b, Supervisor, :terminate_child, [Jido.Supervisor, c.jido])
    dispatch(c, parent, Directive.spawn_agent(RemoteCounter, :worker, node: c.node_b))
    assert {{:spawn_agent_failed, _}, %{status: :failed}} = failure(c)
    assert peer_call(c.peer_a, Jido, :whereis_agent, [c.jido, "parent/worker"]) == nil
  end

  test "duplicate tags and an unrelated target identity are rejected", c do
    parent = start_parent(c)

    assert {:ok, other} =
             peer_call(c.peer_b, Jido, :start_agent, [
               c.jido,
               RemoteCounter,
               [id: "parent/worker"]
             ])

    directive = Directive.spawn_agent(RemoteCounter, :worker, node: c.node_b)
    dispatch(c, parent, directive)
    assert {{:spawn_agent_failed, {:child_identity_in_use, "parent/worker"}}, _} = failure(c)
    assert peer_call(c.peer_a, Server, :children, [parent]) == %{}
    assert :ok = peer_call(c.peer_a, Jido, :stop_agent, [c.jido, other])
    dispatch(c, parent, directive)
    first = child(c, parent)
    dispatch(c, parent, directive)
    assert {{:child_tag_in_use, :worker}, _} = failure(c)
    assert child(c, parent).pid == first.pid
    assert length(supervised(c.peer_b, c.jido)) == 1
  end

  test "late startup and repeated pending requests resolve one child identity", c do
    parent = start_parent(c, directive_timeout: 100)
    supervisor = Jido.agent_supervisor_name(c.jido)
    assert :ok = peer_call(c.peer_b, :sys, :suspend, [supervisor])
    directive = Directive.spawn_agent(RemoteCounter, :worker, node: c.node_b)

    try do
      dispatch(c, parent, directive)

      assert {{:child_spawn_indeterminate, :worker, _, request, :timeout},
              %{status: :indeterminate}} = failure(c)

      dispatch(c, parent, Directive.spawn_agent(RemoteCounter, :worker, node: c.node_a))
      assert {{:child_spawn_pending, :worker, _, ^request}, _} = failure(c)
      dispatch(c, parent, directive)
      assert {{:child_spawn_indeterminate, :worker, _, ^request, :timeout}, _} = failure(c)

      assert %{runtime: %{pending_child_spawns: %{worker: %{request_id: ^request}}}} =
               peer_call(c.peer_a, Server, :status, [parent])
    after
      assert :ok = peer_call(c.peer_b, :sys, :resume, [supervisor])
    end

    worker = child(c, parent)
    assert node(worker.pid) == c.node_b
    assert length(supervised(c.peer_b, c.jido)) == 1

    eventually(fn ->
      peer_call(c.peer_a, Server, :status, [parent]).runtime.pending_child_spawns == %{}
    end)

    assert :ok = peer_call(c.peer_a, Server, :stop_child, [parent, :worker])
    assert supervised(c.peer_b, c.jido) == []
  end

  test "parent loss before delayed startup leaves no remote child", c do
    parent = start_parent(c, directive_timeout: 100)
    supervisor = Jido.agent_supervisor_name(c.jido)
    assert :ok = peer_call(c.peer_b, :sys, :suspend, [supervisor])

    try do
      dispatch(c, parent, Directive.spawn_agent(RemoteCounter, :worker, node: c.node_b))
      assert {{:child_spawn_indeterminate, _, _, _, :timeout}, _} = failure(c)
      assert :ok = peer_call(c.peer_a, Jido, :stop_agent, [c.jido, parent])
    after
      assert :ok = peer_call(c.peer_b, :sys, :resume, [supervisor])
    end

    # The supervisor barrier queues a fresh inspection after the delayed start.
    assert supervised(c.peer_b, c.jido) == []
    assert peer_call(c.peer_b, Jido, :whereis_agent, [c.jido, "parent/worker"]) == nil
  end

  test "an old request cannot recreate a stopped child, including after registry restart", c do
    alias Jido.AgentServer.{ChildPlacement, SpawnRegistry}
    parent = start_parent(c)
    directive = Directive.spawn_agent(RemoteCounter, :worker, node: c.node_b)
    dispatch(c, parent, directive)
    first = child(c, parent)
    parent_ref = peer_call(c.peer_b, Server, :status, [first.pid]).runtime.parent

    replay_opts = [
      agent: RemoteCounter,
      id: first.id,
      jido: c.jido,
      parent: parent_ref,
      register: true
    ]

    assert :ok = peer_call(c.peer_a, Server, :stop_child, [parent, :worker])

    assert :ok = peer_call(c.peer_b, Supervisor, :terminate_child, [c.jido, SpawnRegistry])
    assert {:ok, _} = peer_call(c.peer_b, Supervisor, :restart_child, [c.jido, SpawnRegistry])

    assert {:error, :spawn_request_closed} =
             peer_call(c.peer_b, ChildPlacement, :start_local, [c.jido, replay_opts, :transient])

    assert supervised(c.peer_b, c.jido) == []

    dispatch(c, parent, directive)
    next = child(c, parent)
    refute next.pid == first.pid
    assert :ok = peer_call(c.peer_a, Server, :stop_child, [parent, :worker])

    assert {:error, :spawn_request_closed} =
             peer_call(c.peer_b, ChildPlacement, :start_local, [c.jido, replay_opts, :transient])

    assert supervised(c.peer_b, c.jido) == []

    assert length(peer_call(c.peer_b, Jido.RuntimeStore, :list, [c.jido, :agent_spawn_requests])) ==
             1
  end

  test "disconnect keeps closed requests while the parent is still alive", c do
    alias Jido.AgentServer.ChildPlacement
    parent = start_parent(c)

    dispatch(
      c,
      parent,
      Directive.spawn_agent(RemoteCounter, :worker, node: c.node_b, restart: :temporary)
    )

    worker = child(c, parent)
    parent_ref = peer_call(c.peer_b, Server, :status, [worker.pid]).runtime.parent

    replay = [
      agent: RemoteCounter,
      id: worker.id,
      jido: c.jido,
      parent: parent_ref,
      register: true
    ]

    assert peer_call(c.peer_a, Node, :disconnect, [c.node_b])
    assert peer_call(c.peer_a, Process, :alive?, [parent])

    eventually(fn ->
      case peer_call(c.peer_b, Jido.RuntimeStore, :list, [c.jido, :agent_spawn_requests]) do
        [{_, %{status: :closed}}] -> true
        _ -> false
      end
    end)

    eventually(fn -> not peer_call(c.peer_b, Process, :alive?, [worker.pid]) end)
    assert peer_call(c.peer_b, Node, :list, []) == []
    assert peer_call(c.peer_a, Node, :connect, [c.node_b])

    assert {:error, :spawn_request_closed} =
             peer_call(c.peer_b, ChildPlacement, :start_local, [c.jido, replay, :temporary])

    assert supervised(c.peer_b, c.jido) == []
    assert :ok = peer_call(c.peer_a, Jido, :stop_agent, [c.jido, parent])

    eventually(fn ->
      peer_call(c.peer_b, Jido.RuntimeStore, :list, [c.jido, :agent_spawn_requests]) == []
    end)
  end

  test "failed remote stop keeps ownership until the registry is available", c do
    alias Jido.AgentServer.SpawnRegistry
    parent = start_parent(c)
    dispatch(c, parent, Directive.spawn_agent(RemoteCounter, :worker, node: c.node_b))
    worker = child(c, parent)
    assert :ok = peer_call(c.peer_b, Supervisor, :terminate_child, [c.jido, SpawnRegistry])

    assert {:error, {:stop_child_failed, :worker, _}} =
             peer_call(c.peer_a, Server, :stop_child, [parent, :worker])

    assert child(c, parent).pid == worker.pid
    assert peer_call(c.peer_b, Process, :alive?, [worker.pid])
    assert {:ok, _} = peer_call(c.peer_b, Supervisor, :restart_child, [c.jido, SpawnRegistry])
    assert :ok = peer_call(c.peer_a, Server, :stop_child, [parent, :worker])
    assert supervised(c.peer_b, c.jido) == []
  end

  test "a closed late start resolves uncertainty before a new generation", c do
    parent = start_parent(c, directive_timeout: 100)
    supervisor = Jido.agent_supervisor_name(c.jido)
    directive = Directive.spawn_agent(RemoteCounter, :worker, node: c.node_b)
    assert :ok = peer_call(c.peer_b, :sys, :suspend, [supervisor])

    try do
      dispatch(c, parent, directive)
      assert {{:child_spawn_indeterminate, _, _, _, :timeout}, _} = failure(c)
      assert :ok = peer_call(c.peer_a, :sys, :suspend, [parent])

      try do
        assert :ok = peer_call(c.peer_b, :sys, :resume, [supervisor])

        late =
          eventually(fn ->
            peer_call(c.peer_b, Jido, :whereis_agent, [c.jido, "parent/worker"])
          end)

        assert :ok = peer_call(c.peer_b, Jido, :stop_agent, [c.jido, late])
      after
        assert :ok = peer_call(c.peer_a, :sys, :resume, [parent])
      end
    after
      peer_call(c.peer_b, :sys, :resume, [supervisor])
    end

    assert peer_call(c.peer_a, Server, :children, [parent]) == %{}
    dispatch(c, parent, directive)
    assert {{:spawn_agent_failed, :spawn_request_closed}, _} = failure(c)
    assert peer_call(c.peer_a, Server, :status, [parent]).runtime.pending_child_spawns == %{}
    dispatch(c, parent, directive)
    assert node(child(c, parent).pid) == c.node_b
  end

  defp start_parent(c, opts \\ []) do
    {:ok, parent} =
      peer_call(c.peer_a, Fixtures, :start_parent, [c.jido, Keyword.put_new(opts, :id, "parent")])

    parent
  end

  defp dispatch(c, parent, directive) do
    signal = Jido.Signal.new!("test.remote.directive", %{directive: directive}, source: "/test")
    assert {:ok, _} = peer_call(c.peer_a, Server, :call, [parent, signal])
    # A read is processed after the synchronous built-in Directive finishes.
    peer_call(c.peer_a, Server, :status, [parent])
  end

  defp failure(c),
    do: peer_call(c.peer_a, Jido.RuntimeStore, :get, [c.jido, :remote_test_errors, "parent"])

  defp supervised(peer, jido),
    do: peer_call(peer, DynamicSupervisor, :which_children, [Jido.agent_supervisor_name(jido)])

  defp child(c, parent, tag \\ :worker),
    do:
      eventually(fn -> peer_call(c.peer_a, Server, :children, [parent])[tag] end, timeout: 2_000)
end
