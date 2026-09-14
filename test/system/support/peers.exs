Code.require_file("controlled_agent.exs", __DIR__)
Code.require_file("report.exs", __DIR__)
Code.require_file("observability.exs", __DIR__)
Code.require_file("redis.exs", __DIR__)

defmodule JidoTest.System.PeerRuntime do
  @moduledoc false
  use GenServer
  alias Jido.AgentServer, as: Server
  alias Jido.Agent.Directive
  alias JidoTest.RemoteChildFixtures
  alias JidoTest.System.ControlledAgent
  alias JidoTest.RemoteChildFixtures.LifecycleParent
  @instance JidoTest.System.PeerInstance

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def init(_),
    do:
      {:ok,
       %{
         events: [],
         down: [],
         waiters: [],
         event_waiters: [],
         pid_down: [],
         pid_waiters: [],
         pid_refs: %{},
         work_results: %{},
         work_waiters: []
       }}

  def start(namespace, directory, persistence \\ nil) do
    {:ok, _} = Supervisor.start_child(Jido.Supervisor, __MODULE__)

    events =
      for boundary <- [:turn, :commit, :lifecycle, :directive],
          ending <- [:start, :stop, :exception],
          do: [:jido, :agent, boundary, ending]

    :ok = :telemetry.attach_many(__MODULE__, events, &__MODULE__.record/4, namespace)

    {:ok, _} =
      Supervisor.start_child(
        Jido.Supervisor,
        {Jido,
         name: @instance,
         namespace: namespace,
         persistence: persistence || {Jido.Persistence.File, path: directory}}
      )

    :ok
  end

  def start_redis(namespace, socket) do
    persistence =
      {Jido.Persistence.Redis,
       command_fn: &JidoTest.System.RedisServer.command(socket, &1), prefix: "system"}

    start(namespace, nil, persistence)
  end

  def record(event, measures, %{agent_namespace: namespace} = meta, namespace),
    do: GenServer.call(__MODULE__, {:record, {self(), event, measures, meta}})

  def record(_, _, _, _), do: :ok

  def activate(id, restore),
    do:
      Jido.start_agent(@instance, ControlledAgent, id: id, restore: restore, restart: :temporary)

  def activate_parent(id, opts \\ []),
    do:
      Jido.start_agent(
        @instance,
        LifecycleParent,
        Keyword.merge([id: id, restart: :temporary], opts)
      )

  def create_worker(parent, node),
    do: LifecycleParent.create_worker(parent, node, ControlledAgent)

  def activate_startup_parent(id, timeout),
    do:
      RemoteChildFixtures.start_parent(@instance,
        id: id,
        directive_timeout: timeout,
        restart: :temporary
      )

  def request_spawn(parent, node) do
    directive = Directive.spawn_child(ControlledAgent, :worker, node: node, restart: :temporary)
    signal = Jido.Signal.new!("test.remote.directive", %{directive: directive}, source: "/system")
    Server.call(parent, signal)
  end

  def startup_error(id), do: Jido.RuntimeStore.get(@instance, :remote_test_errors, id)
  def whereis(id), do: Jido.whereis_agent(@instance, id)

  def child(parent), do: Server.children(parent)[:worker]
  def observations(parent), do: Server.agent(parent).state.observations
  def stop(server), do: Jido.stop_agent(@instance, server)
  def stop_child(parent), do: Server.stop_child(parent, :worker)

  def pool_size,
    do: DynamicSupervisor.count_children(Jido.agent_supervisor_name(@instance)).active

  def saved(directory, namespace, id, module \\ ControlledAgent) do
    Jido.Persistence.load_agent_with_revision(
      {Jido.Persistence.File, path: directory},
      module,
      id,
      instance: @instance,
      namespace: namespace
    )
  end

  def work(server, value), do: Server.call(server, ControlledAgent.signal(value))
  def snapshot(server), do: Server.snapshot(server)
  def status(server), do: Server.status(server)
  def events, do: GenServer.call(__MODULE__, :events)
  def watch(remote), do: GenServer.call(__MODULE__, {:watch, remote})
  def await_down(remote), do: GenServer.call(__MODULE__, {:await_down, remote}, 10_000)

  def await_event(id, event, count),
    do: GenServer.call(__MODULE__, {:await_event, id, event, count}, 15_000)

  def watch_pid(pid), do: GenServer.call(__MODULE__, {:watch_pid, pid})
  def await_pid_down(pid), do: GenServer.call(__MODULE__, {:await_pid_down, pid}, 10_000)
  def await_work_result(id), do: GenServer.call(__MODULE__, {:await_work_result, id}, 10_000)

  def hold(server) do
    {signal_id, caller, worker, _gate} = hold_releasable(server)
    {signal_id, caller, worker}
  end

  def hold_releasable(server) do
    observer = self()
    gate = make_ref()
    signal = ControlledAgent.signal(-1, gate: gate, observer: observer)

    {:ok, caller} =
      Task.Supervisor.start_child(Jido.task_supervisor_name(@instance), fn ->
        result = Server.call(server, signal, :infinity)
        send(__MODULE__, {:work_result, signal.id, result})
      end)

    receive do
      {:work_held, ^gate, worker} -> {signal.id, caller, worker, gate}
    after
      10_000 -> raise "remote work did not reach its barrier"
    end
  end

  def handle_call({:record, event}, _from, state) do
    state = %{state | events: [event | state.events]}

    {ready, waiting} =
      Enum.split_with(state.event_waiters, fn {id, kind, count, _from} ->
        event_count(state.events, id, kind) >= count
      end)

    for {_, _, _, from} <- ready, do: GenServer.reply(from, :ok)
    {:reply, :ok, %{state | event_waiters: waiting}}
  end

  def handle_call(:events, _from, state), do: {:reply, Enum.reverse(state.events), state}

  def handle_call({:watch, remote}, _from, state) do
    true = Node.monitor(remote, true)
    {:reply, :ok, state}
  end

  def handle_call({:await_down, remote}, from, state) do
    if remote in state.down,
      do: {:reply, :ok, state},
      else: {:noreply, %{state | waiters: [{remote, from} | state.waiters]}}
  end

  def handle_call({:await_event, id, event, count}, from, state) do
    if event_count(state.events, id, event) >= count,
      do: {:reply, :ok, state},
      else: {:noreply, %{state | event_waiters: [{id, event, count, from} | state.event_waiters]}}
  end

  def handle_call({:watch_pid, pid}, _from, state) do
    ref = Process.monitor(pid)
    {:reply, :ok, %{state | pid_refs: Map.put(state.pid_refs, ref, pid)}}
  end

  def handle_call({:await_pid_down, pid}, from, state) do
    if pid in state.pid_down,
      do: {:reply, :ok, state},
      else: {:noreply, %{state | pid_waiters: [{pid, from} | state.pid_waiters]}}
  end

  def handle_call({:await_work_result, id}, from, state) do
    case Map.fetch(state.work_results, id) do
      {:ok, result} -> {:reply, result, state}
      :error -> {:noreply, %{state | work_waiters: [{id, from} | state.work_waiters]}}
    end
  end

  def handle_info({:nodedown, remote}, state) do
    {done, waiting} = Enum.split_with(state.waiters, &(elem(&1, 0) == remote))
    for {_, caller} <- done, do: GenServer.reply(caller, :ok)
    {:noreply, %{state | down: [remote | state.down], waiters: waiting}}
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    if Map.get(state.pid_refs, ref) == pid do
      {ready, waiting} = Enum.split_with(state.pid_waiters, &(elem(&1, 0) == pid))
      for {_, from} <- ready, do: GenServer.reply(from, :ok)

      {:noreply,
       %{
         state
         | pid_down: [pid | state.pid_down],
           pid_waiters: waiting,
           pid_refs: Map.delete(state.pid_refs, ref)
       }}
    else
      {:noreply, state}
    end
  end

  def handle_info({:work_result, id, result}, state) do
    {ready, waiting} = Enum.split_with(state.work_waiters, &(elem(&1, 0) == id))
    for {_, from} <- ready, do: GenServer.reply(from, result)

    {:noreply,
     %{state | work_results: Map.put(state.work_results, id, result), work_waiters: waiting}}
  end

  defp event_count(events, id, kind) do
    Enum.count(events, fn {_pid, event, _measures, meta} ->
      meta[:agent_id] == id and event == kind
    end)
  end
end

defmodule JidoTest.System.Peers do
  @moduledoc false
  import ExUnit.Assertions

  def start!(cookie, on_exit) do
    {:ok, peer, peer_node} =
      :peer.start(%{
        name: :peer.random_name(~c"jido_system"),
        host: ~c"127.0.0.1",
        longnames: true,
        connection: :standard_io,
        args: [
          ~c"+S",
          ~c"2",
          ~c"-setcookie",
          String.to_charlist(cookie),
          ~c"-kernel",
          ~c"inet_dist_use_interface",
          ~c"{127,0,0,1}"
        ],
        wait_boot: 15_000
      })

    on_exit.(fn -> if Process.alive?(peer), do: stop(peer) end)
    :ok = :peer.call(peer, :code, :add_paths, [:code.get_path()])
    {:ok, _} = :peer.call(peer, Application, :ensure_all_started, [:jido])
    :peer.call(peer, Code, :require_file, [__ENV__.file])
    {peer, peer_node}
  end

  def call(peer, function, args \\ []),
    do: :peer.call(peer, JidoTest.System.PeerRuntime, function, args, 20_000)

  def partition({left, left_node}, {right, right_node}) do
    true = :peer.call(left, Node, :set_cookie, [right_node, :jido_system_blocked_left])
    true = :peer.call(right, Node, :set_cookie, [left_node, :jido_system_blocked_right])
    true = :peer.call(left, Node, :disconnect, [right_node])
    :ok = call(left, :await_down, [right_node])
    :ok = call(right, :await_down, [left_node])
    [] = :peer.call(left, Node, :list, [])
    [] = :peer.call(right, Node, :list, [])
    :ok
  end

  def rejoin({left, left_node}, {right, right_node}, cookie) do
    original = String.to_atom(cookie)
    true = :peer.call(left, Node, :set_cookie, [right_node, original])
    true = :peer.call(right, Node, :set_cookie, [left_node, original])
    true = :peer.call(left, Node, :connect, [right_node])
    true = :peer.call(right, Node, :connect, [left_node])
    :ok
  end

  def stop(peer) do
    monitor = Process.monitor(peer)
    :ok = :peer.stop(peer)
    assert_receive {:DOWN, ^monitor, :process, ^peer, _}, 10_000
    :ok
  end

  def crash(peer) do
    pid = :peer.call(peer, System, :pid, [])
    monitor = Process.monitor(peer)
    {_output, 0} = System.cmd("kill", ["-KILL", pid], stderr_to_stdout: true)
    assert_receive {:DOWN, ^monitor, :process, ^peer, _}, 10_000
    :ok
  end
end
