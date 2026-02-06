defmodule JidoExampleTest.TracingTest do
  @moduledoc """
  Example test demonstrating signal tracing and correlation with agents.

  This test shows:
  - How trace context is automatically attached to signals by AgentServer
  - How emitted signals inherit trace_id from the input signal (trace propagation)
  - How parent-child agent communication preserves trace chains
  - How to inspect trace data on signals for debugging/observability

  ## Key Concepts

  - **trace_id**: Shared identifier for the entire request flow
  - **span_id**: Unique identifier for each signal in the chain
  - **parent_span_id**: Links to the span that caused this signal
  - **causation_id**: The signal.id that triggered this signal

  Run with: mix test --include example
  """
  use JidoTest.Case, async: false

  @moduletag :example
  @moduletag timeout: 15_000

  alias Jido.Agent.Directive
  alias Jido.AgentServer
  alias Jido.Signal
  alias Jido.Tracing.Trace

  # ===========================================================================
  # SIGNAL COLLECTOR: Captures emitted signals with trace data
  # ===========================================================================

  defmodule TracedSignalCollector do
    @moduledoc false
    use GenServer

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, [], opts)
    end

    def get_signals(pid) do
      GenServer.call(pid, :get_signals)
    end

    def clear(pid) do
      GenServer.call(pid, :clear)
    end

    @impl true
    def init(_opts) do
      {:ok, []}
    end

    @impl true
    def handle_info({:signal, signal}, signals) do
      {:noreply, [signal | signals]}
    end

    @impl true
    def handle_call(:get_signals, _from, signals) do
      {:reply, Enum.reverse(signals), signals}
    end

    def handle_call(:clear, _from, _signals) do
      {:reply, :ok, []}
    end
  end

  # ===========================================================================
  # ACTIONS: Emit signals to demonstrate trace propagation
  # ===========================================================================

  defmodule StartWorkflowAction do
    @moduledoc false
    use Jido.Action,
      name: "start_workflow",
      schema: [
        workflow_name: [type: :string, required: true]
      ]

    def run(params, _context) do
      event_signal =
        Signal.new!(
          "workflow.started",
          %{name: params.workflow_name, step: 1},
          source: "/workflow-agent"
        )

      {:ok, %{workflow: params.workflow_name, step: 1}, %Directive.Emit{signal: event_signal}}
    end
  end

  defmodule ProcessStepAction do
    @moduledoc false
    use Jido.Action,
      name: "process_step",
      schema: [
        step_number: [type: :integer, required: true]
      ]

    def run(params, context) do
      current_step = Map.get(context.state, :step, 0)
      new_step = params.step_number

      event_signal =
        Signal.new!(
          "workflow.step_completed",
          %{step: new_step, previous: current_step},
          source: "/workflow-agent"
        )

      {:ok, %{step: new_step}, %Directive.Emit{signal: event_signal}}
    end
  end

  defmodule CompleteWorkflowAction do
    @moduledoc false
    use Jido.Action,
      name: "complete_workflow",
      schema: []

    def run(_params, context) do
      workflow = Map.get(context.state, :workflow, "unknown")

      event_signal =
        Signal.new!(
          "workflow.completed",
          %{workflow: workflow, final_step: context.state.step},
          source: "/workflow-agent"
        )

      {:ok, %{status: :completed}, %Directive.Emit{signal: event_signal}}
    end
  end

  # ===========================================================================
  # AGENT: Workflow agent with signal routing
  # ===========================================================================

  defmodule WorkflowAgent do
    @moduledoc false
    use Jido.Agent,
      name: "workflow_agent",
      schema: [
        workflow: [type: :string, default: nil],
        step: [type: :integer, default: 0],
        status: [type: :atom, default: :idle]
      ]

    def signal_routes(_ctx) do
      [
        {"start_workflow", StartWorkflowAction},
        {"process_step", ProcessStepAction},
        {"complete_workflow", CompleteWorkflowAction}
      ]
    end
  end

  # ===========================================================================
  # TESTS: Trace propagation through agent workflows
  # ===========================================================================

  describe "automatic trace attachment" do
    test "AgentServer attaches trace data to incoming signals", %{jido: jido} do
      {:ok, collector} = TracedSignalCollector.start_link()
      on_exit(fn -> if Process.alive?(collector), do: GenServer.stop(collector) end)

      {:ok, pid} =
        Jido.start_agent(jido, WorkflowAgent,
          id: unique_id("workflow"),
          default_dispatch: {:pid, target: collector}
        )

      signal = Signal.new!("start_workflow", %{workflow_name: "onboarding"}, source: "/test")

      assert Trace.get(signal) == nil

      {:ok, _agent} = AgentServer.call(pid, signal)

      eventually(fn ->
        signals = TracedSignalCollector.get_signals(collector)
        signals != []
      end)

      [emitted] = TracedSignalCollector.get_signals(collector)
      trace = Trace.get(emitted)

      assert trace != nil
      assert is_binary(trace.trace_id)
      assert is_binary(trace.span_id)
    end
  end

  describe "trace propagation across signal chains" do
    test "emitted signals share trace_id with input signal", %{jido: jido} do
      {:ok, collector} = TracedSignalCollector.start_link()
      on_exit(fn -> if Process.alive?(collector), do: GenServer.stop(collector) end)

      {:ok, pid} =
        Jido.start_agent(jido, WorkflowAgent,
          id: unique_id("workflow"),
          default_dispatch: {:pid, target: collector}
        )

      signal1 = Signal.new!("start_workflow", %{workflow_name: "payment"}, source: "/test")
      {:ok, _} = AgentServer.call(pid, signal1)

      signal2 = Signal.new!("process_step", %{step_number: 2}, source: "/test")
      {:ok, _} = AgentServer.call(pid, signal2)

      signal3 = Signal.new!("complete_workflow", %{}, source: "/test")
      {:ok, _} = AgentServer.call(pid, signal3)

      eventually(fn ->
        signals = TracedSignalCollector.get_signals(collector)
        match?([_, _, _ | _], signals)
      end)

      signals = TracedSignalCollector.get_signals(collector)
      traces = Enum.map(signals, &Trace.get/1)

      assert length(traces) == 3

      Enum.each(traces, fn trace ->
        assert trace != nil
        assert is_binary(trace.trace_id)
        assert is_binary(trace.span_id)
      end)

      [trace1, trace2, trace3] = traces
      assert trace1.trace_id != trace2.trace_id
      assert trace2.trace_id != trace3.trace_id
    end

    test "single request flow maintains same trace_id across emissions", %{jido: jido} do
      {:ok, collector} = TracedSignalCollector.start_link()
      on_exit(fn -> if Process.alive?(collector), do: GenServer.stop(collector) end)

      {:ok, pid} =
        Jido.start_agent(jido, WorkflowAgent,
          id: unique_id("workflow"),
          default_dispatch: {:pid, target: collector}
        )

      root_trace = Trace.new_root()
      signal = Signal.new!("start_workflow", %{workflow_name: "traced"}, source: "/test")
      {:ok, traced_signal} = Trace.put(signal, root_trace)

      {:ok, _} = AgentServer.call(pid, traced_signal)

      eventually(fn ->
        signals = TracedSignalCollector.get_signals(collector)
        signals != []
      end)

      [emitted] = TracedSignalCollector.get_signals(collector)
      emitted_trace = Trace.get(emitted)

      assert emitted_trace.trace_id == root_trace.trace_id

      assert emitted_trace.parent_span_id == root_trace.span_id

      assert emitted_trace.causation_id == traced_signal.id
    end
  end

  describe "trace data inspection" do
    test "trace data can be extracted for logging/debugging", %{jido: jido} do
      {:ok, collector} = TracedSignalCollector.start_link()
      on_exit(fn -> if Process.alive?(collector), do: GenServer.stop(collector) end)

      {:ok, pid} =
        Jido.start_agent(jido, WorkflowAgent,
          id: unique_id("workflow"),
          default_dispatch: {:pid, target: collector}
        )

      signal = Signal.new!("start_workflow", %{workflow_name: "debug-test"}, source: "/test")
      {:ok, _} = AgentServer.call(pid, signal)

      eventually(fn ->
        signals = TracedSignalCollector.get_signals(collector)
        signals != []
      end)

      [emitted] = TracedSignalCollector.get_signals(collector)

      trace = Trace.get(emitted)
      assert trace.trace_id =~ ~r/^[0-9a-f-]{36}$/
      assert trace.span_id =~ ~r/^[0-9a-f-]{36}$/

      log_metadata = %{
        trace_id: trace.trace_id,
        span_id: trace.span_id,
        parent_span_id: trace.parent_span_id,
        signal_type: emitted.type
      }

      assert log_metadata.trace_id != nil
      assert log_metadata.signal_type == "workflow.started"
    end
  end

  describe "Trace module basics" do
    test "new_root creates independent traces" do
      trace1 = Trace.new_root()
      trace2 = Trace.new_root()

      assert trace1.trace_id != trace2.trace_id
      assert trace1.span_id != trace2.span_id
    end

    test "child_of preserves trace_id and links parent" do
      parent = Trace.new_root()
      causation_id = Signal.ID.generate!()

      child = Trace.child_of(parent, causation_id)

      assert child.trace_id == parent.trace_id
      assert child.span_id != parent.span_id
      assert child.parent_span_id == parent.span_id
      assert child.causation_id == causation_id
    end

    test "put and get round-trip trace data on signals" do
      signal = Signal.new!("test.event", %{}, source: "/test")
      trace = Trace.new_root()

      {:ok, traced} = Trace.put(signal, trace)
      retrieved = Trace.get(traced)

      assert retrieved.trace_id == trace.trace_id
      assert retrieved.span_id == trace.span_id
    end
  end
end
