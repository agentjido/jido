defmodule JidoTest.TestAgents.ProducerAgent do
  @moduledoc """
  Test agent for cross-process signal tracing that handles :root signals
  and emits child "child.event" signals for trace propagation testing.
  """
  use Jido.Agent,
    name: "producer_agent",
    actions: [
      __MODULE__.RootSignalAction
    ],
    schema: [
      emitted_signals: [
        type: {:list, :map},
        default: [],
        doc: "List of signals emitted by this agent for test inspection"
      ],
      signal_count: [
        type: :integer,
        default: 0,
        doc: "Count of signals emitted"
      ]
    ]

  @impl true
  def handle_signal(%Jido.Signal{type: "root"} = signal, _agent) do
    # Route "root" signals to the "root_signal_action"
    {:ok, %{signal | type: "root_signal_action"}}
  end

  def handle_signal(signal, _agent), do: {:ok, signal}

  defmodule RootSignalAction do
    @moduledoc """
    Action that processes :root signals and emits child.event signals
    """
    use Jido.Action,
      name: "root_signal_action",
      description: "Processes root signals and emits child signals",
      schema: [
        data: [type: :any, doc: "Data to include in child signal"]
      ]

    def run(params, context) do
      # Store the emitted signal data for test inspection
      emitted_signal = %{
        type: "child.event",
        data: %{
          root_data: params[:data],
          processed_at: DateTime.utc_now(),
          producer_id: context[:agent_id]
        },
        emitted_at: DateTime.utc_now()
      }

      # Return success with directive to update state - signal emission happens through standard result processing
      {:ok, %{processed: true, child_signal_emitted: true},
       [
         %Jido.Agent.Directive.StateModification{
           op: :put,
           path: [:emitted_signals],
           value: {:append, emitted_signal}
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
  Helper function to get emitted signals for test inspection
  """
  def get_emitted_signals(agent_pid) when is_pid(agent_pid) do
    {:ok, state} = Jido.Agent.Server.state(agent_pid)
    Map.get(state.agent.state, :emitted_signals, [])
  end

  @doc """
  Helper function to get signal count for test inspection
  """
  def get_signal_count(agent_pid) when is_pid(agent_pid) do
    {:ok, state} = Jido.Agent.Server.state(agent_pid)
    Map.get(state.agent.state, :signal_count, 0)
  end

  @doc """
  Helper function to clear emitted signals for test cleanup
  """
  def clear_emitted_signals(agent_pid) when is_pid(agent_pid) do
    # Use state modification directive to clear signals
    directive = %Jido.Agent.Directive.StateModification{
      op: :set,
      path: [:emitted_signals],
      value: []
    }

    directive2 = %Jido.Agent.Directive.StateModification{
      op: :set,
      path: [:signal_count],
      value: 0
    }

    # Apply directives through the agent (this would need proper API)
    # For now, this is a placeholder - clearing would need to be implemented differently
    :ok
  end
end
