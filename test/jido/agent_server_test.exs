defmodule Jido.AgentServerTest do
  use ExUnit.Case, async: false

  alias Jido.Agent
  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.DirectiveContext
  alias Jido.Agent.Turn.Outcome
  alias Jido.Signal
  alias Jido.Signal.ID
  alias JidoTest.AgentFixtures

  alias JidoTest.AgentFixtures.{
    Add,
    BlockingAdd,
    ContinueToAdd,
    Fail,
    InvalidState,
    ObserveExecutionBoundary,
    ReentrantCall,
    WithDirective
  }

  @receive_timeout 2_000

  defmodule SpyExec do
    def run_async(executable, input, context, opts) do
      test_pid =
        Map.get(input, :test_pid) || get_in(input, [:signal, Access.key(:data), :test_pid])

      if test_pid do
        send(test_pid, {:agent_exec_target, executable})
      end

      Jido.Exec.run_async(executable, input, context, opts)
    end

    defdelegate handle_message(handle, message), to: Jido.Exec
    defdelegate cancel(handle), to: Jido.Exec
  end

  defmodule InvalidOutputExec do
    def run_async(_executable, _input, _context, _opts),
      do: Task.async(fn -> {:ok, :not_a_map} end)

    def handle_message(%Task{ref: ref}, {ref, result}), do: {:done, result}
    def handle_message(_task, _message), do: :ignore

    def cancel(task) do
      _result = Task.shutdown(task, :brutal_kill)
      :ok
    end
  end

  defmodule CancellationFailExec do
    defdelegate run_async(executable, input, context, opts), to: Jido.Exec
    defdelegate handle_message(handle, message), to: Jido.Exec
    def cancel(_handle), do: {:error, :cancel_failed}
  end

  defmodule FaultAgent do
    use Jido.Agent, name: "fault_agent"

    @impl Jido.Agent
    def handle_signal(_signal, _agent), do: raise("unexpected callback fault")
  end

  defp schema do
    Zoi.object(%{
      count: Zoi.integer(),
      history: Zoi.list(Zoi.string())
    })
  end

  defp agent(routes) do
    Agent.new!(
      name: "counter",
      schema: schema(),
      routes: routes
    )
    |> Agent.instantiate!(state: %{count: 0, history: []})
  end

  defp signal(type, data \\ %{}) do
    Signal.new!(type: type, source: "/agent-server-test", data: data)
  end

  test "commits one terminal Action output as one complete Agent state" do
    server = start_supervised!({Server, agent: agent([{"counter.add", Add}])})

    assert {:ok, %Agent{state: %{count: 2, history: ["one"]}} = committed} =
             Server.call(server, signal("counter.add", %{by: 2, label: "one"}))

    assert Server.agent(server) == committed
    assert %{phase: :idle, state_version: 1, active: nil} = Server.status(server)
  end

  test "instantiates one neutral Agent definition at the Server boundary" do
    definition = Agent.new!(name: "counter", schema: schema())

    server =
      start_supervised!(
        {Server,
         agent: definition,
         id: "server-definition",
         initial_state: %{count: 2, history: ["initial"]}}
      )

    assert %Agent{
             id: "server-definition",
             state: %{count: 2, history: ["initial"]}
           } = Server.agent(server)

    assert Agent.definition(Server.agent(server)) == definition
  end

  test "does not override an Agent instance at the Server boundary" do
    instance = agent([])

    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Server.start_link(agent: instance, id: "replacement")

    assert message == "Agent Server cannot override an Agent instance with Server options"
  end

  test "keeps executable input separate from committed Agent state" do
    server =
      start_supervised!({Server, agent: agent([{"counter.observe", ObserveExecutionBoundary}])})

    input = %{state: :caller_owned, test_pid: self()}

    assert {:ok, %Agent{state: %{count: 0, history: []}}} =
             Server.call(server, signal("counter.observe", input))

    assert_receive {:agent_execution_boundary, ^input, context}, @receive_timeout
    assert context.agent_state == %{count: 0, history: []}
    assert context.agent_id == Server.agent(server).id
  end

  test "starts the selected executable at the one live Exec boundary" do
    server =
      start_supervised!(
        {Server,
         agent: agent([{"counter.observe", ObserveExecutionBoundary}]), exec_module: SpyExec}
      )

    assert {:ok, _agent} =
             Server.call(server, signal("counter.observe", %{test_pid: self()}))

    assert_receive {:agent_exec_target, ObserveExecutionBoundary}, @receive_timeout
  end

  test "caller context reaches one Turn without changing its Signal or Agent" do
    server =
      start_supervised!({Server, agent: agent([{"counter.observe", ObserveExecutionBoundary}])})

    original = Server.agent(server)
    command = signal("counter.observe", %{test_pid: self()})

    for caller_context <- [%{request: "one"}, [request: "two"], nil] do
      assert {:ok, ^original} = Server.call(server, command, context: caller_context)
      assert_receive {:agent_execution_boundary, input, context}, @receive_timeout
      assert input == command.data
      assert context.signal.data == command.data
      assert context.signal.id == command.id
      assert context.agent_state == original.state
      assert context.agent_id == original.id
      assert Map.get(context, :request) == get_in(caller_context || %{}, [:request])
    end

    # Existing timeout calls and asynchronous requests carry no prior context.
    for timeout <- [5_000, :infinity] do
      assert {:ok, ^original} = Server.call(server, command, timeout)
      assert_receive {:agent_execution_boundary, _, context}, @receive_timeout
      refute Map.has_key?(context, :request)
    end

    request = Server.send_request(server, command)
    assert {:reply, {:ok, ^original}} = Server.receive_response(request)
    assert_receive {:agent_execution_boundary, _, context}, @receive_timeout
    refute Map.has_key?(context, :request)
    assert Server.snapshot(server) == %{agent: original, state_version: 6}
  end

  test "invalid call options and reserved context fail without execution or commit" do
    server =
      start_supervised!(
        {Server,
         agent: agent([{"counter.observe", ObserveExecutionBoundary}]),
         error_policy: fn _, _ -> :continue end}
      )

    before = Server.snapshot(server)
    command = signal("counter.observe", %{test_pid: self()})

    for options <- [
          [context: :invalid],
          [context: [1, 2]],
          [context: command],
          [context: %{agent_state: %{count: 99}}],
          [context: %{agent_id: "replacement"}],
          [context: %{signal: command}],
          [timeout: -1],
          [timeout: :invalid],
          [unknown: true],
          [:invalid]
        ] do
      assert {:error, %Jido.Error.ValidationError{}} = Server.call(server, command, options)
      assert Server.snapshot(server) == before
      refute_received {:agent_execution_boundary, _, _}
    end
  end

  test "stops on an unexpected handle_signal fault" do
    server =
      start_supervised!({Server, agent: FaultAgent.new!(), restart: :temporary})

    monitor = Process.monitor(server)
    :ok = Server.cast(server, signal("fault.raise"))

    assert_receive {:DOWN, ^monitor, :process, ^server, {%RuntimeError{}, _stacktrace}},
                   @receive_timeout
  end

  test "defines Agent Server runtime records with Zoi structs" do
    assert %Zoi.Types.Struct{module: Server.ActiveTurn} = Server.ActiveTurn.schema()
    assert %Zoi.Types.Struct{module: Server.State} = Server.State.schema()
    assert %Zoi.Types.Struct{module: DirectiveContext} = DirectiveContext.schema()
  end

  test "runs an Action continuation chain before the single commit" do
    server = start_supervised!({Server, agent: agent([{"counter.chain", ContinueToAdd}])})

    assert {:ok, %Agent{state: %{count: 3, history: ["continued"]}}} =
             Server.call(server, signal("counter.chain", %{by: 3, label: "continued"}))

    assert %{state_version: 1} = Server.status(server)
  end

  test "runs one multi-step Flow as one turn" do
    flow = AgentFixtures.two_step_flow()
    server = start_supervised!({Server, agent: agent([{"counter.flow", flow}])})

    input = %{
      first_by: 2,
      second_by: 4,
      first_label: "first",
      second_label: "second"
    }

    assert {:ok, %Agent{state: %{count: 6, history: ["first", "second"]}}} =
             Server.call(server, signal("counter.flow", input))

    assert %{state_version: 1} = Server.status(server)
  end

  test "runs a Dispatch continuation inside one Flow turn" do
    flow = AgentFixtures.dispatch_flow()
    server = start_supervised!({Server, agent: agent([{"counter.dispatch", flow}])})

    assert {:ok, %Agent{state: %{count: 5, history: ["dispatched"]}}} =
             Server.call(
               server,
               signal("counter.dispatch", %{by: 5, label: "dispatched"})
             )

    assert %{state_version: 1} = Server.status(server)
  end

  test "keeps status and OTP system requests responsive during a slow turn" do
    routes = [{"counter.block", BlockingAdd}, {"counter.add", Add}]
    server = start_supervised!({Server, agent: agent(routes)})
    gate = make_ref()

    :ok =
      Server.cast(
        server,
        signal("counter.block", %{by: 1, label: "blocked", test_pid: self(), gate: gate})
      )

    assert_receive {:agent_action_blocked, ^gate, worker}, @receive_timeout

    assert %{phase: :running, state_version: 0, active: %{signal_type: "counter.block"}} =
             Server.status(server, 500)

    assert {:running, _data} = :sys.get_state(server, 500)
    assert is_tuple(:sys.get_status(server, 500))

    send(worker, {:release, gate})

    assert {:ok, %Agent{state: %{count: 1}}} =
             Server.call(server, signal("counter.add", %{by: 0, label: "barrier"}))
  end

  test "rejects a synchronous call from the active executable process" do
    server = start_supervised!({Server, agent: agent([{"counter.reentrant", ReentrantCall}])})

    assert {:ok, %Agent{state: %{count: 0}}} =
             Server.call(
               server,
               signal("counter.reentrant", %{server: server, test_pid: self()}),
               2_000
             )

    assert_receive {:agent_reentrant_result, {:error, :reentrant_turn}}, @receive_timeout
    assert Server.status(server).state_version == 1
  end

  test "postpones later Signals in sender order without a private Signal queue" do
    routes = [{"counter.block", BlockingAdd}, {"counter.add", Add}]
    server = start_supervised!({Server, agent: agent(routes)})
    gate = make_ref()

    first =
      signal("counter.block", %{by: 1, label: "first", test_pid: self(), gate: gate})

    caller = Task.async(fn -> Server.call(server, first) end)
    assert_receive {:agent_action_blocked, ^gate, worker}, @receive_timeout

    assert :ok =
             Server.cast(
               server,
               signal("counter.add", %{by: 2, label: "second", test_pid: self()})
             )

    send(worker, {:release, gate})
    assert {:ok, %Agent{state: %{count: 1, history: ["first"]}}} = Task.await(caller)
    assert_receive {:agent_action_ran, "second", _worker}, @receive_timeout

    assert {:ok, %Agent{state: %{count: 6, history: ["first", "second", "third"]}}} =
             Server.call(server, signal("counter.add", %{by: 3, label: "third"}))
  end

  test "does not cancel a started turn when its caller times out" do
    routes = [{"counter.block", BlockingAdd}, {"counter.add", Add}]
    server = start_supervised!({Server, agent: agent(routes)})
    gate = make_ref()
    test_pid = self()

    spawn(fn ->
      result =
        try do
          Server.call(
            server,
            signal("counter.block", %{
              by: 4,
              label: "late",
              test_pid: test_pid,
              gate: gate
            }),
            20
          )
        catch
          :exit, reason -> {:caller_exit, reason}
        end

      send(test_pid, {:short_caller_result, result})
    end)

    assert_receive {:agent_action_blocked, ^gate, worker}, @receive_timeout
    assert_receive {:short_caller_result, {:caller_exit, _reason}}, @receive_timeout

    send(worker, {:release, gate})

    assert {:ok, %Agent{state: %{count: 4, history: ["late", "barrier"]}}} =
             Server.call(server, signal("counter.add", %{by: 0, label: "barrier"}))
  end

  test "reports Exec and finalization failures without changing the Agent" do
    routes = [{"counter.fail", Fail}, {"counter.invalid", InvalidState}]
    test_pid = self()

    policy = fn reason, %Outcome{} = outcome ->
      send(test_pid, {:failed_turn, reason, outcome})
      :continue
    end

    server = start_supervised!({Server, agent: agent(routes), error_policy: policy})
    initial = Server.agent(server)

    assert {:error, %Jido.Action.Error.ExecutionFailureError{} = exec_error} =
             Server.call(server, signal("counter.fail"))

    assert_receive {:failed_turn, ^exec_error,
                    %Outcome{stage: :execute, committed?: false, state_version_before: 0}}

    assert Server.agent(server) == initial

    assert {:error, %Jido.Error.ValidationError{} = final_error} =
             Server.call(server, signal("counter.invalid"))

    assert_receive {:failed_turn, ^final_error,
                    %Outcome{stage: :finalize, committed?: false, state_version_before: 0}}

    assert Server.agent(server) == initial
    assert Process.alive?(server)
  end

  test "contains invalid custom Exec output at the finalization boundary" do
    test = self()

    policy = fn reason, outcome ->
      send(test, {:invalid_exec_output, reason, outcome})
      :continue
    end

    server =
      start_supervised!(
        {Server,
         agent: agent([{"counter.add", Add}]),
         exec_module: InvalidOutputExec,
         error_policy: policy}
      )

    assert {:error, %Jido.Error.ExecutionError{message: message}} =
             Server.call(server, signal("counter.add", %{by: 1, label: "invalid"}))

    assert message == "Agent executable output must be a plain state map"

    assert_receive {:invalid_exec_output, _reason, %Outcome{stage: :finalize, committed?: false}}

    assert Process.alive?(server)
    assert Server.status(server).state_version == 0
  end

  test "applies the error policy when Signal preparation fails" do
    test_pid = self()

    policy = fn reason, %Outcome{} = outcome ->
      send(test_pid, {:prepare_failed, reason, outcome})
      {:stop, {:agent_error, reason}}
    end

    server =
      start_supervised!({Server, agent: agent([]), error_policy: policy, restart: :temporary})

    monitor = Process.monitor(server)

    assert {:error, reason} = Server.call(server, signal("counter.not_routed"))

    assert_receive {:prepare_failed, ^reason,
                    %Outcome{stage: :prepare, committed?: false, state_version_before: 0}}

    assert_receive {:DOWN, ^monitor, :process, ^server, {:shutdown, {:agent_error, ^reason}}},
                   @receive_timeout
  end

  test "cancels active Exec work without a commit" do
    server =
      start_supervised!({Server, agent: agent([{"counter.block", BlockingAdd}]), debug: true})

    gate = make_ref()
    test_pid = self()

    caller =
      Task.async(fn ->
        Server.call(
          server,
          signal("counter.block", %{
            by: 1,
            label: "cancelled",
            test_pid: test_pid,
            gate: gate
          })
        )
      end)

    assert_receive {:agent_action_blocked, ^gate, worker}, @receive_timeout
    monitor = Process.monitor(worker)

    turn_id = Server.status(server).active.turn_id
    assert {:error, :stale_turn} = Server.cancel_turn(server, ID.generate!())

    assert :ok = Server.cancel_turn(server, turn_id)
    assert {:error, :stale_turn} = Server.cancel_turn(server, turn_id)
    assert {:error, :cancelled} = Task.await(caller)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}, @receive_timeout
    assert %Agent{state: %{count: 0, history: []}} = Server.agent(server)

    assert {:ok, [%{metadata: %{outcome: %Outcome{} = outcome}} | _events]} =
             Server.recent_events(server)

    assert outcome.id == turn_id
    assert outcome.status == :cancelled
    refute outcome.committed?
  end

  test "stops after an indeterminate custom Exec cancellation" do
    server =
      start_supervised!(
        {Server,
         agent: agent([{"counter.block", BlockingAdd}]),
         exec_module: CancellationFailExec,
         restart: :temporary}
      )

    gate = make_ref()
    test = self()

    caller =
      Task.async(fn ->
        Server.call(
          server,
          signal("counter.block", %{
            by: 1,
            label: "indeterminate",
            test_pid: test,
            gate: gate
          })
        )
      end)

    assert_receive {:agent_action_blocked, ^gate, _worker}, @receive_timeout
    monitor = Process.monitor(server)

    assert {:error, :cancel_failed} = Server.cancel(server)
    assert {:error, :cancel_failed} = Task.await(caller)

    assert_receive {:DOWN, ^monitor, :process, ^server,
                    {:shutdown, {:exec_cancellation_failed, :cancel_failed}}},
                   @receive_timeout
  end

  test "rejects a custom process name that would disable id registration" do
    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Server.start_link(
               agent: agent([]),
               jido: Jido,
               name: :custom_agent_name,
               register: true
             )

    assert message =~ "name and register: true"
  end

  test "rejects registration without a Registry" do
    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Server.start_link(agent: agent([]), register: true)

    assert message =~ "requires an Agent Registry"
  end

  test "uses a finite postponed Signal admission limit by default" do
    server = start_supervised!({Server, agent: agent([])})

    assert Server.status(server).admission.limit == 1_000
  end

  test "rejects excess postponed calls with a structured overload error" do
    server =
      start_supervised!(
        {Server,
         agent: agent([{"counter.block", BlockingAdd}, {"counter.add", Add}]),
         max_postponed_signals: 0}
      )

    assert :ok = Server.await_ready(server)
    gate = make_ref()

    :ok =
      Server.cast(
        server,
        signal("counter.block", %{by: 1, label: "one", test_pid: self(), gate: gate})
      )

    assert_receive {:agent_action_blocked, ^gate, worker}, @receive_timeout

    assert {:error, {:overloaded, %{limit: 0, postponed: 0}}} =
             Server.call(server, signal("counter.add", %{by: 1, label: "two"}))

    send(worker, {:release, gate})
  end

  test "rejects non-core Directives before commit" do
    server = start_supervised!({Server, agent: agent([{"counter.directive", WithDirective}])})

    assert {:error, %Jido.Error.ValidationError{message: "Agent Directive has no owner"}} =
             Server.call(
               server,
               signal("counter.directive", %{
                 by: 2,
                 label: "not-committed",
                 directive_name: :notify,
                 test_pid: self()
               })
             )

    assert %Agent{state: %{count: 0, history: []}} = Server.agent(server)
  end

  test "rejects the removed custom Directive handler option" do
    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Server.start_link(agent: agent([]), directive_handler: String)

    assert message =~ "use an Agent Plugin"
  end
end
