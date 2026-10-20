Code.require_file("../support.ex", __DIR__)

defmodule JidoTest.AgentServer.ActivationOwnershipTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server.activation", async: false

  import JidoTest.Eventually
  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.{RegistrationGuard, RegistryWorker}
  alias Jido.Error.ValidationError
  alias JidoTest.AgentServer.Fixtures, as: F

  setup do
    F.setup_runtime()
  end

  @tag obligation: "jido.agent_server.activation.I1"
  test "static supervision has stable identities and does not restart an explicit stop", c do
    other = %{c.agent | id: "other-instance"}
    first_spec = Server.child_spec(agent: c.agent, runner: c.runner)
    second_spec = Server.child_spec(agent: other, runner: c.runner)
    assert first_spec.id != second_spec.id
    assert first_spec.id == Server.child_spec(agent: c.agent, runner: c.runner).id
    {:ok, supervisor} = Supervisor.start_link([first_spec, second_spec], strategy: :one_for_one)
    on_exit(fn -> if Process.alive?(supervisor), do: Supervisor.stop(supervisor) end)

    {_, first, _, _} =
      Enum.find(Supervisor.which_children(supervisor), &(elem(&1, 0) == first_spec.id))

    Process.exit(first, :kill)

    assert_eventually(
      match?(
        {_, pid, _, _} when is_pid(pid) and pid != first,
        Enum.find(Supervisor.which_children(supervisor), &(elem(&1, 0) == first_spec.id))
      )
    )

    {_, replacement, _, _} =
      Enum.find(Supervisor.which_children(supervisor), &(elem(&1, 0) == first_spec.id))

    assert Server.agent(Server.Supervisor.worker(replacement)).id == c.agent.id
    Server.stop(Server.Supervisor.worker(replacement))

    assert {_, :undefined, _, _} =
             Enum.find(Supervisor.which_children(supervisor), &(elem(&1, 0) == first_spec.id))
  end

  @tag obligation: ["jido.agent_server.activation.I1", "jido.agent_server.activation.I2"]
  test "instance startup owns one activation in each exact partition", c do
    {:ok, first} = Server.start(agent: c.agent, jido: c.jido, partition: "one")
    {:ok, second} = Server.start(agent: c.agent, jido: c.jido, partition: "two")
    assert Server.whereis(c.jido, c.agent.id, partition: "one") == first
    assert Server.whereis(c.jido, c.agent.id, partition: "two") == second
    assert Server.whereis(c.jido, c.agent.id) == nil

    assert Enum.any?(
             DynamicSupervisor.which_children(Jido.agent_supervisor_name(c.jido)),
             &(elem(&1, 1) == Server.activation(first))
           )

    assert {:error, {:already_started, ^first}} =
             Server.start(agent: c.agent, jido: c.jido, partition: "one")

    assert {:ok, _, []} = Server.call(first, F.signal())
    assert Server.agent(second) == c.agent
  end

  @tag obligation: "jido.agent_server.activation.I2"
  test "equal identities are isolated by instance", c do
    other = Module.concat(__MODULE__, "Other#{System.unique_integer([:positive])}")
    start_supervised!({Jido, name: other})
    {:ok, first} = Server.start(agent: c.agent, jido: c.jido, partition: "tenant")
    {:ok, second} = Server.start(agent: c.agent, jido: other, partition: "tenant")
    assert first != second
    assert Server.whereis(c.jido, c.agent.id, partition: "tenant") == first
    assert Server.whereis(other, c.agent.id, partition: "tenant") == second
  end

  @tag obligation: "jido.agent_server.activation.I2"
  test "startup rejects invalid instance ownership", c do
    for opts <- [
          [jido: c.jido, runner: c.runner],
          [partition: "tenant"],
          [jido: :missing_server_instance],
          [jido: c.jido, partition: ""],
          [jido: c.jido, partition: :bad],
          [jido: 123]
        ] do
      assert {:error, %ValidationError{}} =
               Server.start_link(
                 Keyword.merge(
                   if(Keyword.has_key?(opts, :jido),
                     do: [agent: c.agent],
                     else: [agent: c.agent, runner: c.runner]
                   ),
                   opts
                 )
               )
    end

    assert {:error, %ValidationError{}} = Server.start(agent: c.agent)
    assert {:error, %ValidationError{}} = Server.start(nil)
  end

  @tag obligation: ["jido.agent_server.activation.I2", "jido.agent_server.activation.I4"]
  test "loss of the instance Registry or registration guard stops the owner", c do
    for dependency <- [:registry, :guard] do
      server = F.start(c, jido: c.jido, runner: Jido.exec_runner_name(c.jido))
      turn = F.blocked(server, Jido.exec_runner_name(c.jido))
      ref = Process.monitor(server)

      target =
        case dependency do
          :registry -> Process.whereis(Jido.registry_name(c.jido))
          :guard -> Process.whereis(Jido.registration_guard_name(c.jido))
        end

      Process.exit(target, :kill)
      assert_receive {:DOWN, ^ref, :process, ^server, _}, 1_000
      assert {:error, _} = Server.await(turn.pending, 500)
      F.down(turn.action)
      F.clean(Jido.exec_runner_name(c.jido))

      assert_eventually(Process.whereis(Jido.registry_name(c.jido)) != nil)
      assert_eventually(Process.whereis(Jido.registration_guard_name(c.jido)) != nil)
    end
  end

  @tag obligation: "jido.agent_server.activation.I2"
  test "the registration guard is idempotent and releases a dead owner", c do
    key = RegistrationGuard.registry_key("guard-#{unique_id()}", nil)
    owner = spawn(fn -> receive do: (:stop -> :ok) end)
    on_exit(fn -> if Process.alive?(owner), do: Process.exit(owner, :kill) end)

    assert :ok = RegistrationGuard.claim(c.jido, key, owner, nil)
    assert :ok = RegistrationGuard.claim(c.jido, key, owner, nil)

    assert {:error, {:already_started, ^owner}} =
             RegistrationGuard.claim(c.jido, key, self(), nil)

    Process.exit(owner, :kill)
    assert_eventually(RegistrationGuard.claim(c.jido, key, self(), nil) == :ok)
    assert :ok = RegistrationGuard.claim(c.jido, key, self(), nil)
  end

  @tag obligation: "jido.agent_server.activation.I2"
  test "recovery stops an orphan before it reuses the Agent identity", c do
    {activation, activation_ref} = spawn_monitor(fn -> receive do: (:stop -> :ok) end)
    {owner, owner_ref} = spawn_monitor(fn -> receive do: (:stop -> :ok) end)

    on_exit(fn ->
      Process.exit(activation, :kill)
      Process.exit(owner, :kill)
    end)

    key = RegistrationGuard.registry_key("orphan-#{unique_id()}", nil)
    assert :ok = RegistrationGuard.claim(c.jido, key, owner, activation)

    assert {:error, {:already_started, ^owner}} =
             RegistrationGuard.claim(c.jido, key, self(), nil)

    Process.exit(activation, :kill)
    assert_receive {:DOWN, ^activation_ref, :process, ^activation, :killed}
    assert :ok = RegistrationGuard.claim(c.jido, key, self(), nil)
    assert_receive {:DOWN, ^owner_ref, :process, ^owner, :killed}
    assert :ok = RegistrationGuard.claim(c.jido, key, self(), nil)
  end

  @tag obligation: "jido.agent_server.activation.I2"
  test "a replaced guard seeds live Registry claims", c do
    key = RegistrationGuard.registry_key("seed-#{unique_id()}", nil)
    registry = Jido.registry_name(c.jido)
    observer = self()

    owner =
      spawn(fn ->
        {:ok, _} = Registry.register(registry, key, :ready)
        send(observer, {:registered, self()})
        receive do: (:stop -> :ok)
      end)

    on_exit(fn -> if Process.alive?(owner), do: Process.exit(owner, :kill) end)
    assert_receive {:registered, ^owner}, 1_000
    old_guard = Process.whereis(Jido.registration_guard_name(c.jido))
    Process.exit(old_guard, :kill)
    F.down(old_guard)

    assert_eventually(
      match?(
        pid when is_pid(pid) and pid != old_guard,
        Process.whereis(Jido.registration_guard_name(c.jido))
      )
    )

    assert_eventually(
      RegistrationGuard.claim(c.jido, key, self(), nil) ==
        {:error, {:already_started, owner}}
    )

    send(owner, :stop)
    assert_eventually(RegistrationGuard.claim(c.jido, key, self(), nil) == :ok)
  end

  @tag obligation: "jido.agent_server.activation.I2"
  test "an isolated guard follows Registry loss and keeps existing claims" do
    instance = Module.concat(__MODULE__, "GuardInstance#{System.unique_integer([:positive])}")
    registry_name = Jido.registry_name(instance)
    {:ok, guard} = RegistrationGuard.start_link(jido: instance)
    Process.unlink(guard)

    assert :sys.get_state(guard).registry_pid == nil
    {:ok, registry} = Registry.start_link(keys: :unique, name: registry_name)
    Process.unlink(registry)

    on_exit(fn ->
      if Process.alive?(guard), do: GenServer.stop(guard)
      if pid = Process.whereis(registry_name), do: Supervisor.stop(pid)
    end)

    assert_eventually(:sys.get_state(guard).registry_pid == registry)
    registry_ref = :sys.get_state(guard).registry_ref
    assert is_reference(registry_ref)
    send(guard, :watch_registry)
    assert_eventually(:sys.get_state(guard).registry_ref == registry_ref)

    key = RegistrationGuard.registry_key("retained-#{unique_id()}", nil)
    owner = spawn(fn -> receive do: (:stop -> :ok) end)
    on_exit(fn -> if Process.alive?(owner), do: Process.exit(owner, :kill) end)
    assert :ok = RegistrationGuard.claim(instance, key, owner, nil)

    send(guard, {:DOWN, make_ref(), :process, self(), :ignored})

    assert_eventually(
      match?(%{registry_pid: ^registry, registry_ref: ^registry_ref}, :sys.get_state(guard))
    )

    Process.exit(registry, :kill)
    F.down(registry)
    assert_eventually(:sys.get_state(guard).registry_pid == nil)

    registry_prefix = Atom.to_string(registry_name) <> "."

    assert_eventually(
      Enum.all?(Process.registered(), fn name ->
        not String.starts_with?(Atom.to_string(name), registry_prefix)
      end)
    )

    observer = self()
    {:ok, replacement} = Registry.start_link(keys: :unique, name: registry_name)
    Process.unlink(replacement)

    second_owner =
      spawn(fn ->
        {:ok, _} = Registry.register(registry_name, key, :ready)
        {:ok, _} = Registry.register(registry_name, :unrelated, :ready)
        send(observer, {:replacement_registry, self()})
        receive do: (:stop -> :ok)
      end)

    on_exit(fn -> if Process.alive?(second_owner), do: Process.exit(second_owner, :kill) end)
    assert_receive {:replacement_registry, ^second_owner}, 1_000
    assert_eventually(:sys.get_state(guard).registry_pid == replacement)
    assert is_reference(:sys.get_state(guard).registry_ref)

    assert RegistrationGuard.claim(instance, key, self(), nil) ==
             {:error, {:already_started, owner}}

    send(second_owner, :stop)
  end

  @tag obligation: "jido.agent_server.activation.I2"
  test "the registration guard reports unavailability", c do
    guard = Process.whereis(Jido.registration_guard_name(c.jido))
    :sys.suspend(c.jido_pid)

    try do
      Process.exit(guard, :kill)
      F.down(guard)

      assert RegistrationGuard.claim(
               c.jido,
               RegistrationGuard.registry_key("missing-#{unique_id()}", nil),
               self(),
               nil
             ) == {:error, :registration_guard_unavailable}
    after
      :sys.resume(c.jido_pid)
    end
  end

  @tag obligation: "jido.agent_server.activation.I2"
  test "the Registry worker retries a bounded name conflict" do
    name = Module.concat(__MODULE__, "RetryRegistry#{System.unique_integer([:positive])}")
    {:ok, conflict} = Registry.start_link(keys: :unique, name: name)

    starter =
      Task.async(fn ->
        case RegistryWorker.start_link(keys: :unique, name: name) do
          {:ok, registry} = result ->
            Process.unlink(registry)
            result

          error ->
            error
        end
      end)

    F.elapsed(30)
    Supervisor.stop(conflict)
    assert {:ok, registry} = Task.await(starter, 2_000)
    assert Process.alive?(registry)

    assert %{start: {RegistryWorker, :start_link, [[keys: :unique, name: ^name]]}} =
             RegistryWorker.child_spec(keys: :unique, name: name)

    Supervisor.stop(registry)
  end

  @tag obligation: "jido.agent_server.activation.I4"
  test "supported OTP names resolve only a live AgentServer", c do
    registry = Module.concat(__MODULE__, "Names#{System.unique_integer([:positive])}")
    start_supervised!({Registry, keys: :unique, name: registry})
    local = Module.concat(__MODULE__, "Local#{System.unique_integer([:positive])}")

    for name <- [
          local,
          {:global, {__MODULE__, make_ref()}},
          {:via, Registry, {registry, make_ref()}}
        ] do
      server = F.start(c, name: name)
      assert Server.alive?(name)
      assert Server.agent(name) == c.agent
      Server.stop(server)
      refute Server.alive?(name)
    end

    refute Server.alive?(self())
    refute Server.alive?(:missing_server_name)
    refute Server.alive?({:bad, :name})
  end

  @tag obligation: "jido.agent_server.activation.I3"
  test "fixed instance defaults are consumed once and explicit values win", c do
    previous = Application.fetch_env(:jido, Server)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:jido, Server, value)
        :error -> Application.delete_env(:jido, Server)
      end
    end)

    Application.put_env(:jido, Server, turn_timeout: 0)
    instance = Module.concat(__MODULE__, "Configured#{System.unique_integer([:positive])}")

    start_supervised!(
      {Jido, name: instance, agent_server: [turn_timeout: 100, debug: true, debug_max_events: 2]}
    )

    {:ok, server} = Server.start(agent: c.agent, jido: instance)
    assert {:ok, _, []} = Server.call(server, F.signal())
    assert length(Server.history(server)) == 1
    turn = F.blocked(server, Jido.exec_runner_name(instance))
    assert {:error, :turn_timeout} = Server.await(turn.pending, 1_000)
    Application.put_env(:jido, Server, turn_timeout: :infinity)
    turn = F.blocked(server, Jido.exec_runner_name(instance))
    assert {:error, :turn_timeout} = Server.await(turn.pending, 1_000)
    Server.stop(server)

    {:ok, explicit} =
      Server.start(agent: c.agent, jido: instance, turn_timeout: :infinity, debug: false)

    turn = F.blocked(explicit, Jido.exec_runner_name(instance))
    F.release(turn)
    assert {:ok, _, []} = Server.await(turn.pending)
    assert Server.history(explicit) == []
    F.clean(Jido.exec_runner_name(instance))
  end
end
