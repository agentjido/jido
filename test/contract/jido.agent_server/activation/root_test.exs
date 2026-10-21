Code.require_file("../support.ex", __DIR__)

defmodule JidoTest.AgentServer.ActivationRootTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server.activation", async: false

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

  defmodule WorkerPlugin do
    use Jido.Plugin

    def child_spec(init),
      do: %{id: __MODULE__, start: {Resource, :start_link, [init]}, shutdown: 50}

    def await_ready(root, opts) do
      send(opts[:observer], {:ready_gate, self(), root})
      receive do: (:release -> :ok)
    end
  end

  defmodule Tree do
    use Supervisor
    def start_link(init), do: Supervisor.start_link(__MODULE__, init)

    def init(init) do
      Supervisor.init([%{id: :leaf, start: {Resource, :start_link, [init]}}],
        strategy: :one_for_one
      )
    end
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
      name: "activation_root_contract",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
      extensions:
        Enum.map(plugins, fn {provider, options} ->
          %{id: provider.id(), provider: provider, vsn: provider.vsn(), data: Map.new(options)}
        end),
      routes: [%{path: "work", handler: %{kind: :action, target: F.Work}}]
    })
    |> Jido.Agent.instantiate!(id: id)
  end

  defp child(root, id), do: root |> Supervisor.which_children() |> List.keyfind(id, 0) |> elem(1)

  @tag obligation: "jido.agent_server.activation.I1"
  test "the activation root owns the request worker and uses standard OTP child types", c do
    server = F.start(c)
    activation = Server.activation(server)
    assert activation != server
    assert {:supervisor, Server.Supervisor, 1} == :proc_lib.translate_initial_call(activation)
    assert [{Server, ^server, :worker, _}] = Supervisor.which_children(activation)
    assert Server.child_spec(agent: c.agent, runner: c.runner).type == :supervisor
    assert Server.stop(server) == :ok
    refute Process.alive?(activation)
  end

  @tag obligation: "jido.agent_server.activation.I1"
  test "the activation table and lifetime cell have one stable shape", c do
    {Server.Supervisor, :start_link, [opts, nil, lifetime]} =
      Server.Supervisor.start_spec(agent: c.agent, runner: c.runner)

    assert opts[:agent] == c.agent
    assert :atomics.get(lifetime, 1) == 0
    assert_raise ArgumentError, fn -> :atomics.get(lifetime, 2) end

    server = F.start(c)
    {:idle, data} = :sys.get_state(server)
    assert :ets.info(data.activation_state, :type) == :set
    assert Server.Supervisor.parent(data.activation_state) == nil

    assert :atomics.info(:ets.lookup_element(data.activation_state, :durable_lifetime, 2)).size ==
             1

    {:ok, direct_root} = Server.Supervisor.start_link(agent: c.agent, runner: c.runner)
    Process.unlink(direct_root)
    direct = Server.Supervisor.worker(direct_root)
    {_phase, direct_data} = :sys.get_state(direct)

    assert :atomics.info(:ets.lookup_element(direct_data.activation_state, :durable_lifetime, 2)).size ==
             1

    assert Server.stop(direct) == :ok
  end

  @tag obligation: "jido.agent_server.activation.I1"
  test "failed parent attachment stops the provisional activation", c do
    before = MapSet.new(:ets.all())
    state = :ets.new(__MODULE__, [:set, :public])

    parent = %{
      activation: self(),
      placement: :owned,
      state: state,
      tag: :missing,
      token: make_ref()
    }

    assert {:error, :parent_changed} =
             Server.Supervisor.start_link([agent: c.agent, runner: c.runner], parent)

    leaked =
      :ets.all()
      |> Enum.reject(&MapSet.member?(before, &1))
      |> Enum.filter(fn table -> :ets.info(table, :name) == Server.Supervisor end)

    assert leaked == []
  end

  @tag obligation: ["jido.agent_server.activation.I4", "jido.agent_server.activation.I5"]
  test "required roots recover as one group before readiness is published", c do
    server = F.start(%{c | agent: agent("recovery", [{WorkerPlugin, observer: c.observer}])})
    activation = Server.activation(server)
    assert_receive {:resource, first, %{agent_server: ^server}}, 1_000
    assert_receive {:ready_gate, gate, ^first}, 1_000
    send(gate, :release)
    assert Server.await_ready(server) == :ok
    assert {:ok, %{state: %{count: 1}} = committed, []} = Server.call(server, F.signal())

    Process.exit(first, :kill)
    F.down(server)
    assert_receive {:resource, second, %{agent_server: replacement}}, 1_000
    assert replacement != server
    assert second != first
    assert Server.activation(replacement) == activation
    assert GenServer.call(second, :owner) == replacement
    assert_receive {:ready_gate, next_gate, ^second}, 1_000
    assert Server.call(replacement, F.signal()) == {:error, :not_ready}
    send(next_gate, :release)
    assert Server.await_ready(replacement) == :ok
    assert Server.agent(replacement) == committed
    assert Server.status(replacement).state_version == 1
  end

  @tag obligation: "jido.agent_server.activation.I5"
  test "execution cleanup keeps failed ownership records", c do
    for {reason, result} <- [
          {:normal, :ok},
          {:scope_failed, {:error, {:ownership_scope_failed, :scope_failed}}}
        ] do
      scope =
        spawn(fn ->
          receive do
            {:system, _from, {:terminate, :normal}} -> exit(reason)
          end
        end)

      on_exit(fn -> Process.exit(scope, :kill) end)
      monitor = Process.monitor(scope)
      state = :ets.new(__MODULE__, [:set, :public])
      execution = {:execution, c.runner, make_ref(), scope}
      :ets.insert(state, execution)

      assert Server.Supervisor.close_execution(state) == result
      assert_receive {:DOWN, ^monitor, :process, ^scope, ^reason}
      assert Server.Supervisor.execution(state) == if(result == :ok, do: nil, else: execution)
    end
  end

  @tag obligation: "jido.agent_server.activation.I5"
  test "recovery keeps admission closed until the old execution scope stops", c do
    server = F.start(c, turn_timeout: :infinity)
    root = Server.activation(server)
    old = F.blocked(server, c.runner)

    [{scope, _}] =
      Registry.lookup(Module.concat(c.runner, Registry), {Runic.TaskScope, old.worker})

    true = :erlang.suspend_process(scope)

    try do
      Process.exit(server, :kill)
      F.down(server)

      assert_eventually(
        match?(pid when is_pid(pid) and pid != server, Server.Supervisor.worker(root))
      )

      replacement = Server.Supervisor.worker(root)
      assert Server.status(replacement).phase == :initializing
      refute Server.status(replacement).ready?
      assert Server.call(replacement, F.signal()) == {:error, :not_ready}
      assert Process.alive?(old.action)

      true = :erlang.resume_process(scope)
      assert Server.await_ready(replacement) == :ok
      refute Process.alive?(scope)
      refute Process.alive?(old.worker)
      refute Process.alive?(old.action)
    after
      resume_scope(scope)
    end
  end

  @tag obligation: "jido.agent_server.activation.I5"
  test "recovery stops the activation when cleanup exceeds the readiness budget", c do
    server = F.start(c, turn_timeout: :infinity, readiness_timeout: 300)
    root = Server.activation(server)
    old = F.blocked(server, c.runner)

    [{scope, _}] =
      Registry.lookup(Module.concat(c.runner, Registry), {Runic.TaskScope, old.worker})

    true = :erlang.suspend_process(scope)

    try do
      Process.exit(server, :kill)
      F.down(server)
      F.down(root)
      assert Process.alive?(old.action)
    after
      resume_scope(scope)
    end

    F.down(scope)
    F.down(old.action)
    F.down(old.worker)
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server.activation.I5"
  test "restart intensity stops the complete activation", c do
    server = F.start(%{c | agent: agent("intensity", [{TreePlugin, observer: c.observer}])})
    activation = Server.activation(server)
    assert Server.await_ready(server) == :ok

    for _ <- 1..3 do
      previous = Server.Supervisor.worker(activation)
      Process.exit(previous, :kill)
      F.down(previous)

      assert_eventually(
        match?(pid when is_pid(pid) and pid != previous, Server.Supervisor.worker(activation))
      )

      assert Server.await_ready(Server.Supervisor.worker(activation)) == :ok
    end

    last = Server.Supervisor.worker(activation)
    Process.exit(last, :kill)
    F.down(activation)
    F.down(last)
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server.activation.I11"
  test "worker recovery drops owned child records with their private supervisor", c do
    parent = F.start(%{c | agent: agent("parent")})
    parent_root = Server.activation(parent)
    {:ok, owned} = Server.spawn_child(parent, agent("owned"), :owned)
    owned_root = Server.activation(owned)

    Process.exit(parent, :kill)
    F.down(parent)
    F.down(owned_root)

    replacement = Server.Supervisor.worker(parent_root)
    assert replacement != parent
    assert Server.children(replacement) == %{}
    assert DynamicSupervisor.which_children(child(parent_root, :owned_agents)) == []
    assert {:ok, _} = Server.spawn_child(replacement, agent("fresh"), :owned)
  end

  @tag obligation: "jido.agent_server.activation.I11"
  test "worker recovery keeps independent child records", c do
    parent = F.start(c, jido: c.jido, runner: Jido.exec_runner_name(c.jido))
    root = Server.activation(parent)

    {:ok, child} =
      Server.spawn_child(parent, agent("independent"), :independent, placement: :independent)

    child_root = Server.activation(child)
    Process.exit(parent, :kill)
    F.down(parent)
    replacement = Server.Supervisor.worker(root)
    assert Server.await_ready(replacement) == :ok
    assert Server.children(replacement).independent.activation == child_root
    assert Process.alive?(child_root)
  end

  @tag obligation: "jido.agent_server.activation.I11"
  test "child reservations are fenced by caller and token" do
    state = :ets.new(__MODULE__, [:set, :public])
    :ets.insert(state, {:worker, self()})
    first = make_ref()
    wrong = make_ref()

    assert :ok = Server.Supervisor.reserve(state, :child, first, self())
    assert {:error, :tag_in_use} = Server.Supervisor.reserve(state, :child, wrong, self())
    assert :ok = Server.Supervisor.release(state, :child, wrong)

    assert [{{:child, :child}, %{token: ^first, caller: caller}}] =
             :ets.lookup(state, {:child, :child})

    assert caller == self()
    assert :ok = Server.Supervisor.release(state, :child, first)
    assert_receive {:child_released, :child, ^first}
    assert Server.Supervisor.records(state) == []

    dead = spawn(fn -> :ok end)
    F.down(dead)
    :ets.insert(state, {{:child, :child}, %{token: first, caller: dead}})
    assert :ok = Server.Supervisor.reserve(state, :child, wrong, self())
    assert [{{:child, :child}, %{token: ^wrong}}] = :ets.lookup(state, {:child, :child})

    :ets.delete(state)
    assert :ok = Server.Supervisor.release(state, :child, wrong)
  end

  @tag obligation: "jido.agent_server.activation.I11"
  test "a child record replaces only its matching reservation" do
    state = :ets.new(__MODULE__, [:set, :public])
    :ets.insert(state, {:worker, self()})
    token = make_ref()
    root = spawn(fn -> receive do: (:stop -> :ok) end)
    on_exit(fn -> if Process.alive?(root), do: Process.exit(root, :kill) end)
    :ets.insert(state, {{:child, :child}, %{token: token, caller: self()}})

    parent = %{
      activation: self(),
      placement: :owned,
      restart: :temporary,
      state: state,
      tag: :child,
      token: token
    }

    assert :ok = Server.Supervisor.record_child(parent, root)
    assert_receive {:child_registered, :child, ^token, ^root}

    assert {:error, :tag_in_use} =
             Server.Supervisor.reserve(state, :child, make_ref(), self())

    assert [
             {{:child, :child},
              %{
                placement: :owned,
                restart: :temporary,
                restart?: false,
                root: ^root,
                token: ^token
              }}
           ] = Server.Supervisor.records(state)

    assert {:error, :parent_changed} =
             Server.Supervisor.record_child(%{parent | token: make_ref()}, root)

    next = make_ref()
    :ets.insert(state, {{:child, :next}, %{token: next, caller: self()}})
    next_parent = parent |> Map.delete(:restart) |> Map.merge(%{tag: :next, token: next})

    assert :ok =
             Server.Supervisor.record_child(next_parent, root)

    assert_receive {:child_registered, :next, ^next, ^root}

    assert [{{:child, :next}, %{restart?: true, restart: :transient}}] =
             :ets.lookup(state, {:child, :next})

    :ets.insert(state, {:parent, parent})
    assert Server.Supervisor.parent(state) == parent

    :ets.delete(state)
    assert {:error, :parent_changed} = Server.Supervisor.record_child(parent, root)

    stopped = spawn(fn -> :ok end)
    F.down(stopped)
    assert :ok = Server.Supervisor.record_child(%{parent | activation: stopped}, root)
  end

  @tag obligation: "jido.agent_server.activation.I11"
  test "the owned child supervisor is one idempotent supervisor", c do
    server = F.start(c)
    root = Server.activation(server)
    assert {:ok, child_supervisor} = Server.Supervisor.child_supervisor(root)
    assert {:ok, ^child_supervisor} = Server.Supervisor.child_supervisor(root)

    assert {:owned_agents, ^child_supervisor, :supervisor, [DynamicSupervisor]} =
             List.keyfind(Supervisor.which_children(root), :owned_agents, 0)
  end

  @tag obligation: "jido.agent_server.activation.I5"
  test "missing execution ownership is explicit and forget removes a record", c do
    state = :ets.new(__MODULE__, [:set, :public])

    assert Server.Supervisor.remember_execution(state, c.runner, make_ref(), self()) ==
             {:error, :ownership_scope_unavailable}

    execution = {:execution, c.runner, make_ref(), self()}
    :ets.insert(state, execution)
    assert Server.Supervisor.execution(state) == execution
    assert Server.Supervisor.forget_execution(state) == :ok
    assert Server.Supervisor.execution(state) == nil
    assert Server.Supervisor.forget_execution(nil) == :ok

    root = F.start_activation(c)
    server = Server.Supervisor.worker(root)
    assert :ok = Supervisor.terminate_child(root, Server)
    assert Server.Supervisor.worker(root) == nil
    assert :ok = Supervisor.stop(root)
    refute Process.alive?(server)
  end

  defp resume_scope(scope) do
    :erlang.resume_process(scope)
  catch
    :error, :badarg -> :ok
  end
end
