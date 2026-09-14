Code.require_file("adapters.exs", __DIR__)
Code.require_file("observability.exs", __DIR__)
Code.require_file("fault_adapter.exs", __DIR__)
Code.require_file("controlled_agent.exs", __DIR__)
Code.require_file("migration_agent.exs", __DIR__)
Code.require_file("bus_agent.exs", __DIR__)

for file <- ~w(checkpoints effects fencing recovery execution restoration overload topology),
    do: Code.require_file("scenarios/#{file}.exs", __DIR__)

defmodule JidoTest.System.Case do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      import JidoTest.Case, only: [unique_id: 0, unique_id: 1]
      import JidoTest.System.Case
      @moduletag :tmp_dir
      @moduletag timeout: 120_000
    end
  end

  setup context do
    isolate_log_group()
    jido = :"system_#{System.unique_integer([:positive])}"
    namespace = Atom.to_string(jido)
    observer = JidoTest.System.Observability.start!(namespace, &on_exit/1, context)
    store = JidoTest.System.Adapters.start!(context.adapter, context.tmp_dir, observer)

    world =
      start_supervised!(%{
        id: :system_world,
        restart: :temporary,
        start:
          {Supervisor, :start_link,
           [
             [{Jido, name: jido, namespace: namespace, persistence: store}],
             [strategy: :rest_for_one]
           ]},
        type: :supervisor
      })

    jido_pid = Process.whereis(jido)

    sink =
      start_supervised!(
        {JidoTest.RecoverableDeliverySink,
         jido: jido,
         observer: self(),
         on_attempt: &JidoTest.System.Observability.effect_attempt(observer, &1)}
      )

    control = start_supervised!({Agent, fn -> [] end}, id: :checkpoint_fault)

    on_exit(fn ->
      refute Process.alive?(jido_pid)
      assert Process.whereis(jido) == nil
    end)

    {:ok,
     store: store,
     persistence: {JidoTest.System.FaultAdapter, store: store, control: control},
     control: control,
     jido: jido,
     jido_pid: jido_pid,
     world: world,
     namespace: namespace,
     sink: sink,
     observer: observer}
  end

  defp isolate_log_group do
    original = Process.group_leader()
    leader = spawn(fn -> forward_io(original) end)
    Process.group_leader(self(), leader)
    {:ok, supervisor} = ExUnit.fetch_test_supervisor()
    Process.group_leader(supervisor, leader)

    on_exit(fn ->
      monitor = Process.monitor(leader)
      send(leader, :stop)
      assert_receive {:DOWN, ^monitor, :process, ^leader, :normal}, 5_000
    end)
  end

  defp forward_io(original) do
    receive do
      {:io_request, _, _, _} = request ->
        send(original, request)
        forward_io(original)

      :stop ->
        :ok
    end
  end

  def start_agent(context, opts \\ []) do
    {module, opts} = Keyword.pop(opts, :module, JidoTest.RecoverableDeliveryAgent)

    opts =
      Keyword.merge(
        [
          id: JidoTest.Case.unique_id(),
          persistence: context.persistence,
          restore: false,
          restart: :temporary
        ],
        opts
      )

    {:ok, server} = Jido.start_agent(context.jido, module, opts)
    server
  end

  def load(context, id, module \\ JidoTest.RecoverableDeliveryAgent) do
    Jido.Persistence.load_agent_with_revision(
      context.store,
      module,
      id,
      instance: context.jido,
      namespace: context.namespace
    )
  end

  def read_bytes(adapter, key, opts) do
    case adapter.get(key, opts) do
      {:ok, bytes, _token} -> {:ok, bytes}
      result -> result
    end
  end

  def kill_agent(context, server) do
    monitors = monitor_agent_tree(context, server)
    JidoTest.System.Observability.killed(context.observer, server)
    Process.exit(server, :kill)
    await_down(monitors)
    assert_empty_agent_pool(context)
  end

  def monitor_agent_tree(context, server) do
    # These recovery scenarios own exactly one Agent. Include the pool's Plugin
    # lifecycle wrappers, not only the public Plugin runtime PIDs.
    pool = DynamicSupervisor.which_children(Jido.agent_supervisor_name(context.jido))
    roots = for {_, pid, _, _} <- pool, is_pid(pid), do: pid
    for pid <- Enum.uniq([server | roots ++ child_pids(server)]), do: {pid, Process.monitor(pid)}
  end

  def await_down(monitors) do
    for {pid, ref} <- monitors, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 10_000)
  end

  def child_pids(server) do
    Jido.AgentServer.children(server)
    |> Map.values()
    |> Enum.map(& &1.pid)
    |> Enum.filter(&is_pid/1)
    |> Enum.uniq()
  end

  def assert_empty_agent_pool(context),
    do:
      assert(
        DynamicSupervisor.count_children(Jido.agent_supervisor_name(context.jido)).active == 0
      )

  def stop_agent(context, server) do
    ref = Process.monitor(server)
    :ok = Jido.stop_agent(context.jido, server)
    assert_receive {:DOWN, ^ref, :process, ^server, _}, 10_000
  end

  def completed(context, server, records) do
    if map_size(records) > 0,
      do: JidoTest.System.Observability.await_turn(context.observer, server, 2)

    assert Jido.AgentServer.agent(server).state.delivery == %{pending: %{}, completed: records}
  end
end
