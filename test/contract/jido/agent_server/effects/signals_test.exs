Code.require_file("../support.ex", __DIR__)

defmodule JidoTest.AgentServer.Effects.SignalsTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server.effects", async: false

  import JidoTest.Eventually
  alias Jido.Agent.Directive.Emit
  alias Jido.Agent.Directive
  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.Directive.{ErrorReport, ServerStop}
  alias Jido.Signal.Bus
  alias Jido.Tracing.Trace
  alias JidoTest.AgentServer.Fixtures, as: F

  defmodule SignalContextPlugin do
    use Jido.Plugin

    def prepare_dispatch(nil, signal, context, opts) do
      send(opts[:observer], {:dispatch_context, context})
      {:ok, signal}
    end
  end

  setup do
    F.setup_runtime()
  end

  @tag obligation: ["jido.agent_server.effects.I6", "jido.agent_server.effects.I7"]
  test "nil Emit defaults to self after commit", c do
    server = F.start(c)
    assert {:ok, saved, [_]} = Server.call(server, batch([%Emit{signal: F.signal(%{amount: 4})}]))
    assert saved.state.count == 1
    assert_eventually(Server.status(server).state_version == 2)
    assert Server.agent(server).state.count == 5
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server.effects.I6"
  test "default dispatch and explicit override carry causation", c do
    server = F.start(c, default_dispatch: {:pid, target: self()})
    source = batch([%Emit{signal: F.signal(%{}, "out")}])
    assert {:ok, _, _} = Server.call(server, source)
    assert_receive {:signal, signal}, 1_000
    assert Trace.get(signal).causation_id == source.id
    assert_eventually(Server.status(server).phase == :idle)
    assert Server.status(server).state_version == 1
    observer = self()

    sink =
      spawn(fn ->
        receive do
          {:signal, value} -> send(observer, {:explicit_delivered, value})
        end
      end)

    directives = [%Emit{signal: F.signal(), dispatch: {:pid, target: sink}}]
    assert {:ok, _, _} = Server.call(server, batch(directives))
    assert_eventually(Server.status(server).phase == :idle)
    refute_received {:signal, _}
    assert_receive {:explicit_delivered, _}, 1_000
    F.down(sink)
  end

  @tag obligation: "jido.agent_server.effects.I7"
  test "self cast acceptance does not promise admission or delivery", c do
    server = F.start(c, max_postponed_signals: 0, directive_handler: fn _, _ -> :ok end)
    directives = [%Emit{signal: F.signal()}, %F.Effect{}]
    assert {:ok, _, _} = Server.call(server, batch(directives))
    assert_eventually(Server.status(server).phase == :idle)
    assert Server.status(server).last_effect_outcome.status == :succeeded
    assert Server.status(server).state_version == 1
  end

  @tag obligation: "jido.agent_server.effects.I8"
  test "ServerStop must be last and exits only after commit", c do
    server = F.start(c)
    ref = Process.monitor(server)

    assert {:error, :terminal_directive_not_last} =
             Server.call(server, batch([%ServerStop{}, %Emit{signal: F.signal()}]))

    F.unchanged(server, c.agent)

    assert {:ok, %{state: %{count: 1}}, [%ServerStop{}]} =
             Server.call(server, batch([%ServerStop{reason: :done}]))

    assert_receive {:DOWN, ^ref, :process, ^server, {:shutdown, :done}}, 1_000
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server.effects.I9"
  test "reported error applies failure policy after commit and stops the batch", c do
    observer = self()

    server =
      F.start(c,
        error_policy: fn reason, summary ->
          send(observer, {:policy, reason, summary})
          :continue
        end
      )

    directives = [
      %ErrorReport{error: "private error"},
      %Emit{signal: F.signal(), dispatch: {:pid, target: self()}}
    ]

    assert {:ok, saved, ^directives} = Server.call(server, batch(directives))

    assert_receive {:policy, {:reported_error, nil, "private error"},
                    %{committed?: true, stage: :directive, status: :failed}},
                   1_000

    assert_eventually(Server.status(server).phase == :idle)
    assert Server.agent(server) == saved
    assert Server.status(server).last_outcome.status == :succeeded
    assert Server.status(server).last_effect_outcome.status == :failed
    assert Server.status(server).error_count == 1
    refute_received {:signal, _}
  end

  @tag obligation: "jido.agent_server.effects.I9"
  test "reported errors can stop the activation after its success reply", c do
    server = F.start(c, error_policy: :stop_on_error)
    ref = Process.monitor(server)
    assert {:ok, _, _} = Server.call(server, batch([%ErrorReport{error: :reported}]))
    assert_receive {:DOWN, ^ref, :process, ^server, {:shutdown, :agent_error}}, 1_000
  end

  @tag obligation: "jido.agent_server.effects.I9"
  test "reported error Signals contain the committed failure summary", c do
    server = F.start(c, error_policy: {:emit_signal, {:pid, target: self()}})

    assert {:ok, saved, _} =
             Server.call(server, batch([%ErrorReport{error: "PRIVATE_REPORTED_ERROR"}]))

    assert_receive {:signal, signal}, 1_000
    assert signal.type == "jido.agent_server.error"
    assert %{committed?: true, stage: :directive, status: :failed} = signal.data
    refute inspect(signal.data) =~ "PRIVATE_REPORTED_ERROR"
    assert_eventually(Server.status(server).phase == :idle)
    assert Server.agent(server) == saved
    assert Server.status(server).last_outcome.status == :succeeded
  end

  @tag obligation: ["jido.agent_server.effects.I6", "jido.agent_server.effects.I9"]
  test "Bus targets inherit their instance and retain an explicit foreign scope", c do
    other = Module.concat(__MODULE__, "BusInstance#{System.unique_integer([:positive])}")
    start_supervised!({Jido, name: other})
    first = start_supervised!({Bus, name: :scoped, jido: c.jido})
    second = start_supervised!({Bus, name: :scoped, jido: other})
    {:ok, _} = Bus.subscribe(first, "out")
    {:ok, _} = Bus.subscribe(second, "out")
    server = F.start(c, jido: c.jido, runner: Jido.exec_runner_name(c.jido))

    directives =
      for target <- [{:bus, target: :scoped}, {:bus, target: :scoped, jido: other}],
          do: %Emit{signal: F.signal(%{}, "out"), dispatch: target}

    assert {:ok, _, _} = Server.call(server, batch(directives))
    assert_receive {:signal, signal}, 1_000
    assert_receive {:signal, other_signal}, 1_000
    assert signal.id != other_signal.id
    assert_eventually(Server.status(server).phase == :idle)
    assert Server.status(server).last_effect_outcome.status == :succeeded
    Server.stop(server)
    {:ok, _} = Bus.subscribe(first, "jido.agent_server.error")

    policy_server =
      F.start(c,
        jido: c.jido,
        runner: Jido.exec_runner_name(c.jido),
        error_policy: {:emit_signal, {:bus, target: :scoped}}
      )

    assert {:ok, _, _} =
             Server.call(policy_server, batch([%ErrorReport{error: :reported}]))

    assert_receive {:signal,
                    %{
                      type: "jido.agent_server.error",
                      data: %{status: :failed, stage: :directive}
                    }},
                   1_000
  end

  @tag obligation: "jido.agent_server.effects.I6"
  test "Signal preparation receives the complete Turn and instance context", c do
    observer = Module.concat(__MODULE__, "Observer#{System.unique_integer([:positive])}")
    Process.register(self(), observer)

    assert {:ok, agent, _} =
             Jido.Agent.mutate(c.agent, [
               Directive.plugin_add(SignalContextPlugin, observer: observer)
             ])

    server =
      F.start(%{c | agent: agent},
        jido: c.jido,
        partition: "effects",
        runner: Jido.exec_runner_name(c.jido)
      )

    outbound = F.signal(%{}, "out")
    source = batch([%Emit{signal: outbound, dispatch: {:pid, target: self()}}])
    assert {:ok, _, _} = Server.call(server, source, context: %{token: :local})
    assert_receive {:dispatch_context, context}, 1_000
    assert context.source_signal == source
    assert context.effective_signal == source
    assert context.turn_context == %{token: :local}
    assert context.jido == c.jido
    assert context.partition == "effects"
    assert_receive {:signal, delivered}, 1_000
    assert delivered.id == outbound.id
  end

  @tag obligation: "jido.agent_server.effects.I9"
  test "failed error Signal delivery stops after the turn error reply", c do
    target =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    server = F.start(c, error_policy: {:emit_signal, {:pid, target: target}})
    send(target, :stop)
    F.down(target)
    ref = Process.monitor(server)
    assert {:error, error} = Server.call(server, F.signal(%{mode: :fail}))
    assert inspect(error) =~ "SERVER2_PRIVATE_ERROR"
    assert_receive {:DOWN, ^ref, :process, ^server, {:shutdown, :error_signal_failed}}, 1_000
    F.clean(c.runner)
  end

  @tag obligation: "jido.agent_server.effects.I9"
  test "error Signals contain only summaries and cannot start an emission loop", c do
    server = F.start(c, error_policy: {:emit_signal, {:pid, target: self()}})
    assert {:error, _} = Server.call(server, F.signal(%{mode: :fail, secret: "PRIVATE_INPUT"}))
    assert_receive {:signal, signal}, 1_000
    assert signal.type == "jido.agent_server.error"
    assert signal.data == Server.status(server).last_outcome
    refute inspect(signal) =~ "PRIVATE_INPUT"
    refute inspect(signal) =~ "SERVER2_PRIVATE_ERROR"
    assert Trace.get(signal).causation_id == signal.data.signal_id
    assert {:error, _} = Server.call(server, signal)
    refute_receive {:signal, _}, 30
    assert Server.status(server).error_count == 2
    F.clean(c.runner)
  end

  defp batch(directives), do: F.signal(%{mode: :batch, directives: directives})
end
