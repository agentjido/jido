Code.require_file("../support.ex", __DIR__)

defmodule JidoTest.AgentServer.Effects.CoreTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server.effects", async: false

  import JidoTest.Eventually
  alias Jido.Agent.Directive.Emit
  alias Jido.AgentServer.Directive.ServerStop
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

  @tag obligation: ["jido.agent_server.effects.I1", "jido.agent_server.effects.I4"]
  test "instance and directive options fail before starting invalid processes", c do
    for config <- [
          [directive_timeout: :infinity],
          [max_directives_per_turn: -1],
          [directive_handler: fn _ -> :ok end],
          nil
        ] do
      assert {:error, %ValidationError{}} =
               Jido.start_link(name: :invalid_server_settings, agent_server: config)
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

  @tag obligation: "jido.agent_server.effects.I1"
  test "the full batch is rejected before commit or any dispatch", c do
    good = %Emit{signal: F.signal(%{}, "effect"), dispatch: {:pid, target: self()}}

    for batch <- [
          [%ServerStop{reason: :normal}, good],
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

  @tag obligation: "jido.agent_server.effects.I1"
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

  @tag obligation: ["jido.agent_server.effects.I1", "jido.agent_server.effects.I2"]
  test "a state-only Plugin Directive completes without a runtime handler", c do
    directive = %F.Effect{label: :state_only}
    server = F.start(c)
    assert {:ok, _, [^directive]} = Server.call(server, batch_signal([directive]))
    assert_eventually(Server.status(server).phase == :idle)
    assert Server.status(server).last_effect_outcome.status == :succeeded
  end

  @tag obligation: ["jido.agent_server.effects.I2", "jido.agent_server.effects.I5"]
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

  @tag obligation: ["jido.agent_server.effects.I2", "jido.agent_server.effects.I6"]
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

  @tag obligation: "jido.agent_server.effects.I3"
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

  @tag obligation: "jido.agent_server.effects.I3"
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

  @tag obligation: "jido.agent_server.effects.I4"
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

  @tag obligation: "jido.agent_server.effects.I4"
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

  @tag obligation: "jido.agent_server.effects.I5"
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

  @tag obligation: "jido.agent_server.effects.I5"
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
