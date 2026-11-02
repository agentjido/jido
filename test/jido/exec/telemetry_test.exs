defmodule Jido.Exec.TelemetryTest do
  use Covenant.Case, component: "jido_action.execution", async: false
  @moduletag obligation: "jido_action.execution.I23"

  alias Jido.Action.Error
  alias Jido.Exec
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias Jido.Instruction
  alias Runic.Workflow.SingleOutput.Context

  alias JidoActionTest.Fixtures.Actions.{Add, ErrorAction, ExtrasAction}

  @action_start [:jido, :action, :start]
  @action_stop [:jido, :action, :stop]
  @action_exception [:jido, :action, :exception]
  @flow_start [:jido, :flow, :start]
  @flow_stop [:jido, :flow, :stop]
  @flow_exception [:jido, :flow, :exception]

  defmodule RetryAction do
    use Jido.Action, name: "telemetry_retry"

    @impl true
    def run(%{succeed_on: succeed_on}, %{counter: counter}) do
      attempt = Agent.get_and_update(counter, fn count -> {count + 1, count + 1} end)

      if attempt < succeed_on do
        {:error, Error.execution_error("retry", %{retry: true})}
      else
        {:ok, %{attempt: attempt}}
      end
    end
  end

  test "lists the public Jido Exec telemetry events" do
    assert Jido.Exec.Telemetry.event_names() == [
             @action_start,
             @action_stop,
             @action_exception,
             @flow_start,
             @flow_stop,
             @flow_exception
           ]
  end

  test "Invoke and Handoff Action metadata use the new control names" do
    instruction = Instruction.new!(target: Add)

    invoke =
      Jido.Exec.Node.Action.new(instruction,
        id: :invoke,
        name: "invoke_selector",
        flow: %{component: "next", mode: {:invoke, :expander}}
      )

    handoff =
      Jido.Exec.Node.Action.new(instruction,
        id: :handoff,
        name: "handoff_selector",
        flow: %{component: "next", mode: :handoff}
      )

    assert %{
             node_name: "invoke_selector",
             component_kind: :invoke,
             invoke_phase: :expander
           } = Jido.Exec.Telemetry.action_metadata(invoke, %Context{})

    assert %{
             node_name: "handoff_selector",
             component_kind: :handoff
           } = handoff_metadata = Jido.Exec.Telemetry.action_metadata(handoff, %Context{})

    refute Map.has_key?(handoff_metadata, :invoke_phase)
    refute Map.has_key?(handoff_metadata, :dispatch_phase)

    assert Jido.Exec.Telemetry.result_metadata(:flow, {:handoff, instruction, [:one, :two]}) ==
             %{outcome: :handoff, effect_count: 2}
  end

  test "an Action span contains bounded semantic metadata" do
    token = attach([@action_start, @action_stop, @action_exception])

    assert Exec.run(ExtrasAction, %{value: 7}, %{secret: "do-not-emit"}) ==
             {:ok, %{value: 7}, [%{trace_id: nil}]}

    assert_receive {^token, @action_start, start_measurements, start_metadata}
    assert_receive {^token, @action_stop, stop_measurements, stop_metadata}
    refute_received {^token, @action_exception, _, _}

    assert is_integer(start_measurements.system_time)
    assert is_integer(stop_measurements.duration)

    assert %{
             action: ExtrasAction,
             action_name: "extras_action",
             attempt: 0,
             runnable_id: runnable_id,
             activation_id: runnable_id,
             attempt_id: %Runic.Identity{}
           } = start_metadata

    assert Map.drop(stop_metadata, [:outcome, :effect_count]) == start_metadata
    assert stop_metadata.outcome == :ok
    assert stop_metadata.effect_count == 1

    for metadata <- [start_metadata, stop_metadata] do
      refute Map.has_key?(metadata, :params)
      refute Map.has_key?(metadata, :context)
      refute Map.has_key?(metadata, :result)
      refute Map.has_key?(metadata, :effects)
      refute inspect(metadata) =~ "do-not-emit"
    end
  end

  test "a returned Action error stops its span with an error outcome" do
    token = attach([@action_start, @action_stop, @action_exception])

    assert {:error, %Error.ExecutionFailureError{}} =
             Exec.run(ErrorAction, %{error_type: :runtime})

    assert_receive {^token, @action_start, _, start_metadata}
    assert_receive {^token, @action_stop, _, stop_metadata}
    refute_received {^token, @action_exception, _, _}

    assert Map.drop(stop_metadata, [:outcome, :error_type, :retryable?]) == start_metadata
    assert stop_metadata.outcome == :error
    assert stop_metadata.error_type == :execution_error
    assert stop_metadata.retryable? == false
    refute Map.has_key?(stop_metadata, :error)
    refute Map.has_key?(stop_metadata, :stacktrace)
  end

  test "Action retry spans keep one activation and identify each attempt" do
    token = attach([@action_start, @action_stop])
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    assert Exec.run(RetryAction, %{succeed_on: 3}, %{counter: counter},
             max_attempts: 3,
             backoff: :none
           ) == {:ok, %{attempt: 3}}

    events = receive_events(token, 6)
    starts = metadata_for(events, @action_start)
    stops = metadata_for(events, @action_stop)

    assert Enum.map(starts, & &1.attempt) == [0, 1, 2]
    assert starts |> Enum.map(& &1.activation_id) |> Enum.uniq() |> length() == 1
    assert starts |> Enum.map(& &1.attempt_id) |> Enum.uniq() |> length() == 3
    assert Enum.map(stops, & &1.outcome) == [:error, :error, :ok]
    assert Enum.map(stops, &Map.get(&1, :retryable?)) == [true, true, nil]
  end

  test "an immediate Flow emits one Flow span and Action attempt spans" do
    token =
      attach([
        @flow_start,
        @flow_stop,
        @flow_exception,
        @action_start,
        @action_stop,
        @action_exception
      ])

    flow = one_step_flow("telemetry_flow", Add)
    assert Exec.run(flow, %{value: 2}) == {:ok, %{value: 3}}

    assert [
             {@flow_start, _, flow_start},
             {@action_start, _, action_start},
             {@action_stop, _, action_stop},
             {@flow_stop, _, flow_stop}
           ] = receive_events(token, 4)

    assert flow_start.kind == :flow
    assert flow_start.flow == "telemetry_flow"
    refute Map.has_key?(flow_start, :target)
    assert flow_stop.outcome == :ok
    assert flow_stop.effect_count == 0

    assert action_start.component == "step"
    assert action_start.node_path == ["step"]
    assert action_start.component_kind == :step
    assert action_stop.outcome == :ok
  end

  test "a failed immediate Flow stops both semantic spans with error outcomes" do
    token =
      attach([
        @flow_start,
        @flow_stop,
        @flow_exception,
        @action_start,
        @action_stop,
        @action_exception
      ])

    flow = one_step_flow("telemetry_failure", ErrorAction, %{error_type: :runtime})
    assert {:error, %Error.ExecutionFailureError{}} = Exec.run(flow)

    events = receive_events(token, 4)
    assert metadata_for(events, @action_stop) |> List.first() |> Map.fetch!(:outcome) == :error
    assert metadata_for(events, @flow_stop) |> List.first() |> Map.fetch!(:outcome) == :error
    assert metadata_for(events, @action_exception) == []
    assert metadata_for(events, @flow_exception) == []
  end

  defmodule KillAction do
    use Jido.Action, name: "telemetry_kill"

    @impl true
    def run(_params, _context), do: Process.exit(self(), :kill)
  end

  test "a Flow span stops when its execution task is killed" do
    token = attach([@flow_start, @flow_stop, @flow_exception])

    flow = one_step_flow("telemetry_kill", KillAction, %{})
    assert {:error, %Error.ExecutionFailureError{}} = Exec.run(flow)

    events = receive_events(token, 2)
    assert [%{outcome: :error}] = metadata_for(events, @flow_stop)
    assert metadata_for(events, @flow_exception) == []
  end

  test "managed execution combines Jido Action spans with Runic runtime events" do
    runic_workflow_start = [:runic, :runner, :workflow, :start]
    runic_workflow_stop = [:runic, :runner, :workflow, :stop]
    runic_runnable_start = [:runic, :runner, :runnable, :start]
    runic_runnable_stop = [:runic, :runner, :runnable, :stop]

    token =
      attach([
        @flow_start,
        @flow_stop,
        @action_start,
        @action_stop,
        runic_workflow_start,
        runic_workflow_stop,
        runic_runnable_start,
        runic_runnable_stop
      ])

    runner = __MODULE__.Runner
    start_supervised!({Runic.Runner, name: runner})
    execution_id = {:telemetry, System.unique_integer([:positive])}
    test_pid = self()

    assert {:ok, _worker} =
             Exec.start(
               runner,
               execution_id,
               one_step_flow("managed_telemetry", Add),
               %{value: 4},
               %{},
               hooks: [on_idle: fn _state -> send(test_pid, :managed_telemetry_idle) end]
             )

    assert_receive :managed_telemetry_idle, 1_000

    assert_receive {^token, @action_start, _, %{runnable_id: runnable_id}}, 1_000
    assert_receive {^token, @action_stop, _, %{runnable_id: ^runnable_id}}, 1_000
    assert_receive {^token, ^runic_workflow_start, _, %{id: ^execution_id}}, 1_000
    assert_receive {^token, ^runic_workflow_stop, _, %{id: ^execution_id}}, 1_000
    assert_receive {^token, ^runic_runnable_start, _, %{runnable_id: ^runnable_id}}, 1_000
    assert_receive {^token, ^runic_runnable_stop, _, %{runnable_id: ^runnable_id}}, 1_000

    refute_received {^token, @flow_start, _, _}
    refute_received {^token, @flow_stop, _, _}
    refute_received {^token, @action_start, _, _}
    refute_received {^token, ^runic_workflow_start, _, _}
  end

  def handle_event(event, measurements, metadata, {test_pid, token}) do
    send(test_pid, {token, event, measurements, metadata})
  end

  defp attach(events) do
    token = make_ref()
    handler = {__MODULE__, token}
    :ok = :telemetry.attach_many(handler, events, &__MODULE__.handle_event/4, {self(), token})
    on_exit(fn -> :telemetry.detach(handler) end)
    token
  end

  defp receive_events(token, count) do
    Enum.map(1..count, fn _index ->
      assert_receive {^token, event, measurements, metadata}, 1_000
      {event, measurements, metadata}
    end)
  end

  defp metadata_for(events, event) do
    for {^event, _measurements, metadata} <- events, do: metadata
  end

  defp one_step_flow(name, action, params \\ %{value: Ref.input(:value)}) do
    Flow.new!(%{
      name: name,
      components: [%{kind: :step, name: "step", action: action, params: params}],
      output: Ref.result("step")
    })
  end
end
