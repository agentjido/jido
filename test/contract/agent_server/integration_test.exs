Code.require_file("support.ex", __DIR__)

defmodule JidoTest.AgentServer.IntegrationTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server2", async: false

  import JidoTest.Eventually
  alias Jido.Agent.Directive.Emit
  alias Jido.Agent.Directive.Stop
  alias Jido.AgentServer, as: Server
  alias Jido.Error.ValidationError
  alias Jido.Tracing.Context
  alias Jido.Tracing.Trace
  alias JidoTest.AgentServer.Fixtures, as: F

  defmodule UnownedEffect do
    use Jido.Agent.Directive
    defstruct []
    def validate(%__MODULE__{} = value), do: {:ok, value}
  end

  setup do
    F.setup_runtime()
  end

  @tag obligation: "jido.agent_server2.I35"
  test "static supervision gives distinct stable identities and does not restart explicit stops",
       c do
    other = %{c.agent | id: "other-instance"}
    first_spec = Server.child_spec(agent: c.agent, runner: c.runner)
    second_spec = Server.child_spec(agent: other, runner: c.runner)
    assert first_spec.id != second_spec.id
    assert first_spec == Server.child_spec(agent: c.agent, runner: c.runner)
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

    assert Server.agent(Server.Activation.worker(replacement)).id == c.agent.id
    Server.stop(Server.Activation.worker(replacement))

    assert {_, :undefined, _, _} =
             Enum.find(Supervisor.which_children(supervisor), &(elem(&1, 0) == first_spec.id))
  end

  @tag obligation: ["jido.agent_server2.I35", "jido.agent_server2.I36"]
  test "instance start uses its supervisor and shared Runner with separate partition owners", c do
    {:ok, first} = Server.start(agent: c.agent, jido: c.jido, partition: "one")
    {:ok, second} = Server.start(agent: c.agent, jido: c.jido, partition: "two")
    assert Server.whereis(c.jido, c.agent.id, partition: "one") == first
    assert Jido.whereis_agent(c.jido, c.agent.id, partition: "one") == first
    assert Server.whereis(c.jido, c.agent.id, partition: "two") == second
    assert Server.whereis(c.jido, c.agent.id) == nil

    assert Enum.any?(
             DynamicSupervisor.which_children(Jido.agent_supervisor_name(c.jido)),
             &(elem(&1, 1) == Server.activation(first))
           )

    assert {:error, {:already_started, ^first}} =
             Server.start(agent: c.agent, jido: c.jido, partition: "one")

    assert {:ok, %{state: %{count: 1}}, []} = Server.call(first, F.signal())
    assert Server.agent(second) == c.agent
    F.clean(Jido.exec_runner_name(c.jido))
    Process.exit(first, :kill)

    assert_eventually(
      is_pid(Server.whereis(c.jido, c.agent.id, partition: "one")) and
        Server.whereis(c.jido, c.agent.id, partition: "one") != first
    )

    replacement = Server.whereis(c.jido, c.agent.id, partition: "one")
    assert Server.agent(replacement).id == c.agent.id
    Server.stop(replacement)
    assert Server.whereis(c.jido, c.agent.id, partition: "one") == nil

    assert Enum.all?(
             DynamicSupervisor.which_children(Jido.agent_supervisor_name(c.jido)),
             &(elem(&1, 1) != replacement)
           )
  end

  @tag obligation: "jido.agent_server2.I36"
  test "the same id and partition have distinct owners in separate instances", c do
    other = Module.concat(__MODULE__, "Other#{System.unique_integer([:positive])}")
    start_supervised!({Jido, name: other})
    {:ok, first} = Server.start(agent: c.agent, jido: c.jido, partition: "tenant")
    {:ok, second} = Server.start(agent: c.agent, jido: other, partition: "tenant")
    assert first != second
    assert Server.whereis(c.jido, c.agent.id, partition: "tenant") == first
    assert Server.whereis(other, c.agent.id, partition: "tenant") == second
    assert {:ok, _, []} = Server.call(first, F.signal())
    assert Server.agent(second) == c.agent
  end

  @tag obligation: "jido.agent_server2.I36"
  test "rejects cross-instance Runners, invalid partitions, and missing instances", c do
    for opts <- [
          [jido: c.jido, runner: c.runner],
          [partition: "tenant"],
          [jido: :missing_server2_instance],
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

    standalone = F.start(c, runner: Jido.exec_runner_name(c.jido))
    assert Server.stop(standalone) == :ok
  end

  @tag obligation: "jido.agent_server2.I36"
  test "loss of instance Registry stops the current owner and its execution", c do
    # A direct linked start has no restart policy; the instance still owns registration.
    server = F.start(c, jido: c.jido, runner: Jido.exec_runner_name(c.jido))
    turn = F.blocked(server, Jido.exec_runner_name(c.jido))
    ref = Process.monitor(server)
    Process.exit(Process.whereis(Jido.registry_name(c.jido)), :kill)
    assert {:error, _} = Server.await(turn.pending)
    assert_receive {:DOWN, ^ref, :process, ^server, _}, 1_000
    F.down(turn.action)
    F.down(turn.worker)
  end

  @tag obligation: "jido.agent_server2.I36"
  test "loss of the registration guard stops the owner even while the Registry stays live", c do
    server = F.start(c, jido: c.jido, runner: Jido.exec_runner_name(c.jido))
    turn = F.blocked(server, Jido.exec_runner_name(c.jido))
    ref = Process.monitor(server)
    registry = Process.whereis(Jido.registry_name(c.jido))
    Process.exit(Process.whereis(Jido.registration_guard_name(c.jido)), :kill)
    assert_receive {:DOWN, ^ref, :process, ^server, _}, 1_000
    assert {:error, _} = Server.await(turn.pending, 500)
    assert Process.alive?(registry)
    F.down(turn.action)
    F.clean(Jido.exec_runner_name(c.jido))
  end

  @tag obligation: "jido.agent_server2.I37"
  test "local, global, and via names work and unrelated processes fail the liveness check", c do
    registry = Module.concat(__MODULE__, "Names#{System.unique_integer([:positive])}")
    start_supervised!({Registry, keys: :unique, name: registry})
    local = Module.concat(__MODULE__, "Local#{System.unique_integer([:positive])}")

    for name <- [
          local,
          {:global, {__MODULE__, make_ref()}},
          {:via, Registry, {registry, make_ref()}}
        ] do
      server = F.start(c, name: name)
      assert Server.alive?(server)
      assert Server.alive?(name)
      assert Server.agent(name) == c.agent
      Server.stop(server)
      refute Server.alive?(name)
    end

    refute Server.alive?(self())
    refute Server.alive?(:missing_server2_name)
    refute Server.alive?({:bad, :name})
  end

  @tag obligation: ["jido.agent_server2.I36", "jido.agent_server2.I37"]
  test "an explicit via name can use the same instance registration", c do
    name = {:via, Registry, {Jido.registry_name(c.jido), {:agent, c.agent.id}}}
    server = F.start(c, jido: c.jido, runner: Jido.exec_runner_name(c.jido), name: name)
    assert Server.whereis(c.jido, c.agent.id) == server
    assert Jido.whereis_agent(c.jido, c.agent.id) == server
    assert Server.alive?(name)
  end

  @tag obligation: "jido.agent_server2.I38"
  test "instance settings override global defaults; explicit settings win and remain fixed", c do
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

  @tag obligation: ["jido.agent_server2.I38", "jido.agent_server2.I39", "jido.agent_server2.I43"]
  test "instance and directive options fail before starting invalid processes", c do
    for config <- [
          [turn_timout: 1],
          [directive_timeout: :infinity],
          [max_directives_per_turn: -1],
          [directive_handler: fn _ -> :ok end],
          nil
        ] do
      assert {:error, %ValidationError{}} =
               Jido.start_link(name: :invalid_server2_settings, agent_server: config)
    end

    for opts <- [
          [directive_timeout: -1],
          [directive_timeout: :infinity],
          [directive_timeout: 4_294_967_296],
          [max_directives_per_turn: -1],
          [directive_handler: :bad]
        ] do
      assert {:error, %ValidationError{}} =
               Server.start_link(Keyword.merge([agent: c.agent, runner: c.runner], opts))
    end
  end

  @tag obligation: "jido.agent_server2.I39"
  test "the full batch is rejected before commit or any dispatch", c do
    good = %Emit{signal: F.signal(%{}, "effect"), dispatch: {:pid, target: self()}}

    for batch <- [
          [%Stop{reason: :normal}, good],
          [good, %Emit{signal: :invalid, dispatch: {:pid, target: self()}}],
          [good, %Emit{signal: F.signal(), dispatch: {:pid, target: :bad}}],
          [%UnownedEffect{}]
        ] do
      server = F.start(c)
      assert {:error, _} = Server.call(server, batch_signal(batch), timeout: 1_000)
      F.unchanged(server, c.agent)
      F.clean(c.runner)
      refute_received {:signal, _}
      Server.stop(server)
    end

    server = F.start(c, max_directives_per_turn: 1)
    assert {:error, :too_many_directives} = Server.call(server, batch_signal([good, good]))
    F.unchanged(server, c.agent)
    refute_received {:signal, _}
  end

  @tag obligation: "jido.agent_server2.I39"
  test "batch limits admit the exact boundary and zero admits only an empty batch", c do
    good = %Emit{signal: F.signal(%{}, "effect"), dispatch: {:pid, target: self()}}
    server = F.start(c, max_directives_per_turn: 2)
    assert {:ok, _, [_, _]} = Server.call(server, batch_signal([good, good]))
    assert_receive {:signal, _}, 1_000
    assert_receive {:signal, _}, 1_000
    assert_eventually(Server.status(server).phase == :idle)
    Server.stop(server)
    zero = F.start(c, max_directives_per_turn: 0)
    assert {:ok, saved, []} = Server.call(zero, batch_signal([]))
    assert {:error, :too_many_directives} = Server.call(zero, batch_signal([good]))
    assert Server.agent(zero) == saved
    assert Server.status(zero).state_version == 1
    refute_received {:signal, _}
    F.clean(c.runner)
  end

  @tag obligation: ["jido.agent_server2.I40", "jido.agent_server2.I41", "jido.agent_server2.I44"]
  test "commit replies before effects finish, reads stay live, and queued work waits", c do
    server = F.start(c, directive_handler: &__MODULE__.effect/2)
    effects = for label <- [1, 2], do: %F.Effect{label: label, observer: self(), mode: :gate}
    assert {:ok, saved, ^effects} = Server.call(server, batch_signal(effects), timeout: 1_000)
    assert saved.state.count == 1
    assert_receive {:effect, 1, task, context}, 1_000
    assert context.agent == saved
    assert context.state_version == 1
    assert Server.agent(server) == saved

    assert %{active: %{stage: :effects, committed_version: 1}, effects: %{completed: 0, total: 2}} =
             Server.status(server)

    assert {:error, :not_running} = Server.cancel(server)
    queued = Server.submit(server, F.signal(), context: %{observer: self()})
    assert {:error, :timeout} = Server.await(queued, 0)
    send(task, :probe)
    assert_receive {:effect_probe, {:error, :reentrant_turn}, {:error, :reentrant_turn}}
    send(task, :release)
    assert_receive {:effect, 2, second_task, _}, 1_000
    assert Server.status(server).effects.completed == 1
    send(second_task, :release)
    assert {:ok, %{state: %{count: 2}}, []} = Server.await(queued)

    assert Server.status(server).last_effect_outcome == %{
             turn_id: context.turn_id,
             status: :succeeded,
             completed: 2,
             total: 2,
             committed_version: 1,
             stage: :directive
           }

    F.clean(c.runner)
  end

  @tag obligation: ["jido.agent_server2.I40", "jido.agent_server2.I41"]
  test "explicit Signal directives dispatch in order with the turn trace and causation", c do
    server = F.start(c)

    effects =
      for label <- [1, 2],
          do: %Emit{
            signal: F.signal(%{label: label}, "outbound"),
            dispatch: {:pid, target: self()}
          }

    parent = Trace.new_root()
    {:ok, signal} = Trace.put(batch_signal(effects), parent)
    assert {:ok, _, ^effects} = Server.call(server, signal)
    assert_receive {:signal, first}, 1_000
    assert_receive {:signal, second}, 1_000
    assert [first.data.label, second.data.label] == [1, 2]
    assert Trace.get(first).trace_id == parent.trace_id
    assert Trace.get(first).causation_id == signal.id
    assert_eventually(Server.status(server).phase == :idle)
    assert Server.status(server).last_effect_outcome.completed == 2
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server2.I42"
  test "returned error, exception, and invalid result stop a batch without reversing commit", c do
    for mode <- [:fail, :raise, :invalid] do
      server = F.start(c, directive_handler: &__MODULE__.effect/2, debug: true)

      batch = [
        %F.Effect{label: 1, mode: mode, observer: self()},
        %F.Effect{label: 2, observer: self()}
      ]

      assert {:ok, saved, ^batch} = Server.call(server, batch_signal(batch), timeout: 1_000)
      assert_receive {:effect, 1, _, _}, 1_000
      queued = Server.submit(server, F.signal())
      assert {:ok, %{state: %{count: 2}}, []} = Server.await(queued)
      assert Server.status(server).last_effect_outcome.status == :failed
      assert Server.status(server).last_effect_outcome.completed == 0
      assert hd(Server.history(server)).status == :succeeded
      assert saved.state.count == 1
      refute_received {:effect, 2, _, _}
      F.clean(c.runner)
      Server.stop(server)
    end
  end

  @tag obligation: "jido.agent_server2.I42"
  test "a dispatch failure preserves its commit and stops the remaining batch", c do
    target =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    send(target, :stop)
    F.down(target)

    batch = [
      %Emit{signal: F.signal(), dispatch: {:pid, target: target}},
      %Emit{signal: F.signal(), dispatch: {:pid, target: self()}}
    ]

    server = F.start(c)
    assert {:ok, saved, ^batch} = Server.call(server, batch_signal(batch), timeout: 1_000)
    assert_eventually(Server.status(server).phase == :idle)

    assert %{status: :failed, completed: 0, committed_version: 1} =
             Server.status(server).last_effect_outcome

    assert Server.agent(server) == saved
    assert Server.status(server).last_outcome.committed?
    refute_received {:signal, _}
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server2.I43"
  test "effect deadline kills owned work before queued turns and preserves the commit", c do
    server =
      F.start(c,
        directive_handler: &__MODULE__.effect/2,
        turn_timeout: 50,
        directive_timeout: 150
      )

    assert {:ok, _, _} =
             Server.call(
               server,
               batch_signal([%F.Effect{label: 1, mode: :gate, observer: self()}])
             )

    assert_receive {:effect, 1, task, context}, 1_000
    send(server, {:turn_timeout, context.turn_id})
    queued = Server.submit(server, F.signal())
    assert {:ok, %{state: %{count: 2}}, []} = Server.await(queued)
    F.down(task)
    assert %{status: :timed_out, committed_version: 1} = Server.status(server).last_effect_outcome
    send(server, {:effect_timeout, context.turn_id})
    assert %{state_version: 2, phase: :idle} = Server.status(server)
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server2.I43"
  test "a late effect result cannot bypass its deadline even when queued first", c do
    server = F.start(c, directive_handler: &__MODULE__.effect/2, directive_timeout: 150)

    assert {:ok, _, _} =
             Server.call(
               server,
               batch_signal([%F.Effect{label: 1, mode: :gate, observer: self()}])
             )

    assert_receive {:effect, 1, task, _}, 1_000
    :sys.suspend(server)
    on_exit(fn -> if Process.alive?(server), do: :sys.resume(server) end)
    send(task, :release)
    F.down(task)
    F.elapsed(170)
    :sys.resume(server)
    assert_eventually(Server.status(server).phase == :idle)
    assert %{status: :timed_out, completed: 0} = Server.status(server).last_effect_outcome
    assert Server.status(server).last_outcome.committed?
  end

  @tag obligation: "jido.agent_server2.I44"
  test "explicit stop and owner death stop active directive tasks", c do
    for how <- [:stop, :kill] do
      server = F.start(c, directive_handler: &__MODULE__.effect/2)

      assert {:ok, _, _} =
               Server.call(
                 server,
                 batch_signal([%F.Effect{label: 1, mode: :gate, observer: self()}])
               )

      assert_receive {:effect, 1, task, _}, 1_000

      case how do
        :stop -> Server.stop(server)
        :kill -> Process.exit(server, :kill)
      end

      F.down(server)
      F.down(task)
      F.clean(c.runner)
    end
  end

  @tag obligation: "jido.agent_server2.I44"
  test "lost effect task stops the activation after commit with one safe effect outcome", c do
    server = F.start(c, directive_handler: &__MODULE__.effect/2)

    assert {:ok, _, _} =
             Server.call(
               server,
               batch_signal([%F.Effect{label: 1, mode: :gate, observer: self()}])
             )

    assert_receive {:effect, 1, task, _}, 1_000
    assert Server.status(server).last_outcome.committed?
    ref = Process.monitor(server)
    Process.exit(task, :kill)
    assert_receive {:DOWN, ^ref, :process, ^server, {:shutdown, :effect_lifecycle_failed}}, 1_000
    F.clean(c.runner)
  end

  defp batch_signal(batch), do: F.signal(%{mode: :batch, directives: batch})

  def effect(directive, context) do
    assert Context.get().trace_id

    if directive.observer,
      do: send(directive.observer, {:effect, directive.label, self(), context})

    case directive.mode do
      :gate -> wait_effect(directive, context)
      :fail -> {:error, %{private: "PRIVATE_EFFECT_ERROR"}}
      :raise -> raise "PRIVATE_EFFECT_ERROR"
      :invalid -> :invalid
      _ -> :ok
    end
  end

  defp wait_effect(directive, context) do
    receive do
      :release ->
        :ok

      :probe ->
        direct = Server.call(context.server, F.signal())
        nested = Task.async(fn -> Server.call(context.server, F.signal()) end) |> Task.await()
        send(directive.observer, {:effect_probe, direct, nested})
        wait_effect(directive, context)
    end
  end
end
