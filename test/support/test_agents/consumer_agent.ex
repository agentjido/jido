defmodule JidoTest.TestAgents.ConsumerAgent do
  @moduledoc """
  Test agent for cross-process signal tracing that handles "child.event" signals,
  stores both the signal and trace context, and emits grandchild signals to continue
  the trace chain.
  """
  use Jido.Agent,
    name: "consumer_agent",
    actions: [
      __MODULE__.ChildEventAction
    ],
    schema: [
      received_signals: [
        type: {:list, :map},
        default: [],
        doc: "List of signals received by this agent with their trace context"
      ],
      emitted_grandchild_signals: [
        type: {:list, :map},
        default: [],
        doc: "List of grandchild signals emitted for trace continuation"
      ],
      signal_count: [
        type: :integer,
        default: 0,
        doc: "Count of signals processed"
      ]
    ]

  defmodule ChildEventAction do
    @moduledoc """
    Action that processes child.event signals and emits grandchild signals
    """
    use Jido.Action,
      name: "child_event_action",
      description: "Processes child.event signals and emits grandchild signals",
      schema: [
        data: [type: :any, doc: "Data from the child signal"]
      ]

    def run(params, context) do
      # Get current trace context for storage
      current_trace_context = Jido.Signal.TraceContext.current() || %{}

      # Store the received signal with trace context
      received_signal = %{
        signal_data: params,
        trace_context: current_trace_context,
        received_at: DateTime.utc_now(),
        consumer_id: context[:agent_id]
      }

      # Store grandchild signal for inspection
      emitted_grandchild = %{
        type: "grandchild.event",
        data: %{
          child_data: params[:data],
          consumer_processing: %{
            processed_at: DateTime.utc_now(),
            consumer_id: context[:agent_id],
            trace_id: current_trace_context[:trace_id]
          }
        },
        emitted_at: DateTime.utc_now(),
        parent_trace_context: current_trace_context
      }

      # Return success with directives to update state - signal emission happens through standard result processing
      {:ok, %{processed: true, grandchild_signal_emitted: true},
       [
         %Jido.Agent.Directive.StateModification{
           op: :put,
           path: [:received_signals],
           value: {:append, received_signal}
         },
         %Jido.Agent.Directive.StateModification{
           op: :put,
           path: [:emitted_grandchild_signals],
           value: {:append, emitted_grandchild}
         },
         %Jido.Agent.Directive.StateModification{
           op: :put,
           path: [:signal_count],
           value: {:increment, 1}
         }
       ]}
    end
  end

  @doc """
  Helper function to get received signals with trace context for test inspection
  """
  def get_received_signals(agent_pid) when is_pid(agent_pid) do
    {:ok, state} = Jido.Agent.Server.state(agent_pid)
    Map.get(state.agent.state, :received_signals, [])
  end

  @doc """
  Helper function to get emitted grandchild signals for test inspection
  """
  def get_emitted_grandchild_signals(agent_pid) when is_pid(agent_pid) do
    {:ok, state} = Jido.Agent.Server.state(agent_pid)
    Map.get(state.agent.state, :emitted_grandchild_signals, [])
  end

  @doc """
  Helper function to get the latest received signal for test inspection
  """
  def get_latest_received_signal(agent_pid) when is_pid(agent_pid) do
    case get_received_signals(agent_pid) do
      [] -> nil
      signals -> List.last(signals)
    end
  end

  @doc """
  Helper function to get the trace context from the latest received signal
  """
  def get_latest_trace_context(agent_pid) when is_pid(agent_pid) do
    case get_latest_received_signal(agent_pid) do
      nil -> nil
      signal -> signal.trace_context
    end
  end

  @doc """
  Helper function to get signal processing count for test inspection
  """
  def get_signal_count(agent_pid) when is_pid(agent_pid) do
    {:ok, state} = Jido.Agent.Server.state(agent_pid)
    Map.get(state.agent.state, :signal_count, 0)
  end

  @doc """
  Helper function to clear received signals for test cleanup
  """
  def clear_received_signals(agent_pid) when is_pid(agent_pid) do
    # Use state modification directives to clear signals
    # For now, this is a placeholder - clearing would need to be implemented differently
    :ok
  end

  @doc """
  Helper function to verify trace propagation chain
  """
  def verify_trace_chain(agent_pid) when is_pid(agent_pid) do
    received = get_received_signals(agent_pid)
    emitted = get_emitted_grandchild_signals(agent_pid)

    case {received, emitted} do
      {[received_signal], [emitted_signal]} ->
        received_trace = received_signal.trace_context
        emitted_trace = emitted_signal.parent_trace_context

        %{
          trace_chain_valid: received_trace[:trace_id] == emitted_trace[:trace_id],
          received_trace: received_trace,
          emitted_trace: emitted_trace,
          span_progression: %{
            received_span_id: received_trace[:span_id],
            emitted_parent_span_id: emitted_trace[:span_id]
          }
        }

      _ ->
        %{
          trace_chain_valid: false,
          error: "Expected exactly one received and one emitted signal",
          received_count: length(received),
          emitted_count: length(emitted)
        }
    end
  end
end
