defmodule Jido.AgentServerContextTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.Signal

  defmodule ContextPlugin do
    use Jido.Plugin

    @impl true
    def admit(_runtime, command, _opts) do
      if gate = Map.get(command.context, :gate) do
        send(command.context.observer, {:admission_blocked, gate, self()})

        receive do
          {:release, ^gate} -> :ok
        end
      end

      send(command.context.observer, {:context_admitted, command.context, command.signal})
      {:ok, %{command | context: Map.put(command.context, :admitted, true)}}
    end

    @impl true
    def prepare(command, _opts) do
      {:ok, %{command | context: Map.put(command.context, :prepared, true)}}
    end

    @impl true
    def state_spec(_opts), do: {:context_plugin, Zoi.integer() |> Zoi.default(0)}

    @impl true
    def update_state(state, _directives, _opts), do: {:ok, state + 1}

    @impl true
    def prepare_dispatch(_runtime, signal, context, _opts) do
      send(context.turn_context.observer, {:context_dispatch, signal, context})
      {:ok, signal}
    end

    def child_spec(init),
      do: Supervisor.child_spec({Elixir.Agent, fn -> init end}, id: __MODULE__)
  end

  defmodule Emit do
    use Jido.Action,
      name: "server_context_emit",
      schema: Zoi.object(%{value: Zoi.integer()})

    @impl true
    def run(%{value: value}, context) do
      send(context.observer, {:context_executed, context})
      output = Signal.new!("context.output", %{value: value}, source: "/context-test")
      {:ok, %{context.agent_state | value: value}, [Jido.Agent.Directive.emit(output)]}
    end
  end

  defmodule Agent do
    use Jido.Agent,
      name: "server_context_agent",
      schema: Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)}),
      routes: [{"context.input", Emit}],
      plugins: [ContextPlugin]
  end

  for failure <- [:exit, :timeout] do
    @failure failure
    test "admission #{@failure} preserves state and releases the worker", %{jido: jido} do
      test = self()

      policy = fn error, outcome ->
        send(test, {:admission_failed, error, outcome})
        :continue
      end

      {:ok, server} =
        Jido.start_agent(jido, Agent, directive_timeout: 10_000, error_policy: policy)

      before = Server.snapshot(server)
      gate = make_ref()

      caller =
        Task.async(fn ->
          Server.call(server, signal("context.input", %{value: 7}),
            context: %{observer: test, gate: gate}
          )
        end)

      assert_receive {:admission_blocked, ^gate, worker}, 2_000
      monitor = Process.monitor(worker)
      {:admitting, state} = :sys.get_state(server)
      %{task: task, timer: timer} = state.admission_task

      send(server, {:timeout, make_ref(), {:admission_timeout, task.ref}})
      send(server, {:timeout, timer, {:admission_timeout, make_ref()}})
      assert Server.status(server).phase == :admitting

      if @failure == :exit do
        Process.exit(worker, :kill)
      else
        send(server, {:timeout, timer, {:admission_timeout, task.ref}})
      end

      assert {:error, error} = Task.await(caller)
      assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}, 2_000
      assert_receive {:admission_failed, ^error, outcome}, 2_000
      assert outcome.stage == :prepare
      assert outcome.status == if(@failure == :exit, do: :failed, else: :timed_out)
      refute outcome.committed?
      assert Server.snapshot(server) == before
      assert Server.status(server).phase == :idle
      refute_received {:context_executed, _}

      send(server, {task.ref, {:error, :stale}})
      send(server, {:timeout, timer, {:admission_timeout, task.ref}})
      assert Server.status(server).phase == :idle

      assert {:ok, committed} =
               Server.call(server, signal("context.input", %{value: 8}),
                 context: %{observer: test}
               )

      assert committed.state == %{value: 8, context_plugin: 1}
    end
  end

  test "admission cancellation stops its worker before the reply", %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, Agent, directive_timeout: 10_000)
    before = Server.snapshot(server)
    test = self()
    gate = make_ref()

    caller =
      Task.async(fn ->
        Server.call(server, signal("context.input", %{value: 7}),
          context: %{observer: test, gate: gate}
        )
      end)

    assert_receive {:admission_blocked, ^gate, worker}, 2_000
    monitor = Process.monitor(worker)
    {:admitting, state} = :sys.get_state(server)
    assert :ok = Server.cancel(server)
    refute Process.alive?(worker)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}, 2_000
    assert {:error, :cancelled} = Task.await(caller)
    assert Process.read_timer(state.admission_task.timer) == false
    assert Server.snapshot(server) == before
    assert Server.status(server).phase == :idle
  end

  test "queued calls retain context when admission is cancelled and excess casts are dropped", %{
    jido: jido
  } do
    observer = self()

    {:ok, server} =
      Jido.start_agent(jido, Agent,
        max_postponed_signals: 1,
        directive_timeout: :infinity,
        default_dispatch: {:pid, target: observer}
      )

    gate = make_ref()

    first =
      Task.async(fn ->
        Server.call(server, signal("context.input", %{value: 1}),
          context: %{observer: observer, gate: gate}
        )
      end)

    assert_receive {:admission_blocked, ^gate, worker}, 2_000
    active = Server.status(server).active
    assert {:error, :stale_turn} = Server.cancel_turn(server, "stale")

    second =
      Task.async(fn ->
        Server.call(server, signal("context.input", %{value: 2}),
          context: %{observer: observer, request: :queued}
        )
      end)

    eventually(fn -> Server.status(server).admission.postponed == 1 end)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert :ok = Server.cast(server, signal("context.input", %{value: 99}))
        assert :ok = Server.cancel_turn(server, active.turn_id)
      end)

    assert log =~ "Signal cast dropped"
    assert {:error, :cancelled} = Task.await(first)
    refute Process.alive?(worker)
    assert {:ok, committed} = Task.await(second)
    assert committed.state == %{value: 2, context_plugin: 1}
    assert_receive {:context_executed, %{request: :queued}}
    eventually(fn -> Server.status(server).phase == :idle end)
    assert Server.snapshot(server) == %{agent: committed, state_version: 1}
  end

  test "admission result releases its monitor and timer", %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, Agent, directive_timeout: 10_000)
    test = self()
    gate = make_ref()

    caller =
      Task.async(fn ->
        Server.call(server, signal("context.input", %{value: 7}),
          context: %{observer: test, gate: gate}
        )
      end)

    assert_receive {:admission_blocked, ^gate, worker}, 2_000
    {:admitting, state} = :sys.get_state(server)
    %{task: task, timer: timer} = state.admission_task
    send(worker, {:release, gate})
    assert {:ok, _} = Task.await(caller)
    eventually(fn -> Server.status(server).phase == :idle end)
    assert Process.read_timer(timer) == false
    {:monitors, monitors} = Process.info(server, :monitors)
    refute {:process, worker} in monitors
    send(server, {task.ref, {:error, :stale}})
    assert Server.status(server).state_version == 1
  end

  test "context crosses Plugin admission and execution but is not copied to state or Signals", %{
    jido: jido
  } do
    {:ok, server} =
      Jido.start_agent(jido, Agent,
        id: unique_id(),
        default_dispatch: {:pid, target: self()}
      )

    command = signal("context.input", %{value: 7})
    private_request = make_ref()

    assert {:ok, committed} =
             Server.call(server, command,
               context: %{
                 observer: self(),
                 private_request: private_request,
                 jido: :caller_cannot_replace_owner,
                 partition: :caller_cannot_replace_partition
               }
             )

    assert_receive {:context_admitted, admitted, ^command}
    assert admitted.private_request == private_request
    assert admitted.jido == jido
    assert admitted.partition == nil
    assert_receive {:context_executed, executed}
    assert executed.admitted
    assert executed.prepared
    assert executed.private_request == private_request
    assert executed.signal.data == command.data
    assert executed.agent_state == %{value: 0, context_plugin: 0}

    assert_receive {:context_dispatch, output, dispatch}
    assert dispatch.turn_context.private_request == private_request
    assert dispatch.source_signal == command
    assert dispatch.effective_signal.data == command.data
    assert dispatch.plugin_state == 1
    assert_receive {:signal, delivered}
    assert delivered == output
    assert delivered.data == %{value: 7}
    refute Map.has_key?(delivered.extensions, "private_request")
    assert committed.state == %{value: 7, context_plugin: 1}
    eventually(fn -> Server.status(server).phase == :idle end)
    assert Server.snapshot(server) == %{agent: committed, state_version: 1}
  end
end
