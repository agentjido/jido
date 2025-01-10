defmodule JidoTest.TestAgents do
  @moduledoc """
  Collection of test agents for various testing scenarios.
  """

  defmodule MinimalAgent do
    @moduledoc "Minimal agent with no schema or actions"
    use Jido.Agent,
      name: "minimal_agent"
  end

  defmodule BasicAgent do
    @moduledoc "Basic agent with simple schema and actions"
    use Jido.Agent,
      name: "basic_agent",
      actions: [
        JidoTest.TestActions.BasicAction,
        JidoTest.TestActions.NoSchema,
        JidoTest.TestActions.EnqueueAction,
        JidoTest.TestActions.RegisterAction,
        JidoTest.TestActions.DeregisterAction
      ],
      schema: [
        location: [type: :atom, default: :home],
        battery_level: [type: :integer, default: 100]
      ]
  end

  defmodule FullFeaturedAgent do
    @moduledoc "Agent with all features enabled and complex schema"
    use Jido.Agent,
      name: "full_featured_agent",
      description: "Tests all agent features",
      category: "test",
      tags: ["test", "full", "features"],
      vsn: "1.0.0",
      actions: [
        JidoTest.TestActions.Add,
        JidoTest.TestActions.Multiply,
        JidoTest.TestActions.DelayAction,
        JidoTest.TestActions.ContextAction
      ],
      schema: [
        value: [
          type: :integer,
          default: 0,
          doc: "Current value"
        ],
        location: [
          type: :atom,
          default: :home,
          doc: "Current location"
        ],
        battery_level: [
          type: :pos_integer,
          default: 100,
          doc: "Battery percentage"
        ],
        status: [
          type: :atom,
          default: :idle,
          doc: "Current status"
        ],
        config: [
          type: :map,
          doc: "Configuration map",
          default: %{}
        ],
        metadata: [
          type: {:map, :atom, :any},
          default: %{},
          doc: "Metadata storage"
        ]
      ]

    @impl true
    def on_before_validate_state(agent) do
      # Add validation timestamp
      new_state = Map.put(agent.state, :last_validated_at, DateTime.utc_now())
      {:ok, %{agent | state: new_state}}
    end

    @impl true
    def on_before_plan(agent, action, params) do
      # Track planned actions
      new_state = Map.update(agent.state, :planned_actions, [{action, params}], & &1)
      {:ok, %{agent | state: new_state}}
    end

    @impl true
    def on_before_run(agent) do
      # Set status to busy
      new_state = Map.put(agent.state, :status, :busy)
      {:ok, %{agent | state: new_state}}
    end

    @impl true
    def on_after_run(agent, result) do
      # Update status and store result summary
      new_state =
        agent.state
        |> Map.put(:status, :idle)
        |> Map.put(:last_result_at, DateTime.utc_now())
        |> Map.put(:last_result_summary, result)

      {:ok, %{agent | state: new_state}}
    end
  end

  defmodule ValidationAgent do
    @moduledoc "Agent focused on testing validation scenarios"
    use Jido.Agent,
      name: "validation_agent",
      schema: [
        required_string: [type: :string, required: true],
        optional_integer: [type: :integer, minimum: 0],
        nested_map: [
          type: :map,
          keys: [
            required_key: [type: :string, required: true],
            optional_key: [type: :string]
          ]
        ],
        enum_field: [type: :atom, values: [:one, :two, :three]],
        list_field: [type: {:list, :string}]
      ]
  end

  defmodule ErrorHandlingAgent do
    @moduledoc "Agent for testing error scenarios and recovery"
    use Jido.Agent,
      name: "error_handling_agent",
      actions: [
        JidoTest.TestActions.Add,
        JidoTest.TestActions.ErrorAction,
        JidoTest.TestActions.CompensateAction
      ],
      schema: [
        should_recover?: [type: :boolean, default: true],
        error_count: [type: :integer, default: 0],
        last_error: [type: :map, default: %{}]
      ]

    @impl true
    def on_error(%{state: %{should_recover?: true}} = agent, result) do
      new_state =
        agent.state
        |> Map.update!(:error_count, &(&1 + 1))
        |> Map.put(:last_error, %{
          type: result.error.__struct__,
          message: result.error.message,
          timestamp: DateTime.utc_now()
        })

      {:ok, %{agent | state: new_state}}
    end

    @impl true
    def on_error(%{state: %{should_recover?: false}} = _agent, result) do
      {:error, result}
    end
  end

  defmodule AsyncAgent do
    @moduledoc "Agent for testing async operations"
    use Jido.Agent,
      name: "async_agent",
      actions: [
        # JidoTest.TestActions.DelayAction,
        # JidoTest.TestActions.StreamingAction,
        # JidoTest.TestActions.ConcurrentAction
      ],
      schema: [
        timeout: [type: :integer, default: 5000],
        parallel_limit: [type: :integer, default: 4],
        active_tasks: [type: {:map, :reference, :any}, default: %{}]
      ]
  end

  defmodule CallbackTrackingAgent do
    @moduledoc "Agent that tracks all callback executions"
    use Jido.Agent,
      name: "callback_tracking_agent",
      actions: [
        JidoTest.TestActions.Add,
        JidoTest.TestActions.Multiply
      ],
      schema: [
        callback_log: [type: {:list, :map}, default: []],
        callback_count: [type: :map, default: %{}]
      ]

    def track_callback(agent, callback_name) do
      entry = %{
        callback: callback_name,
        timestamp: DateTime.utc_now(),
        state_snapshot: agent.state
      }

      new_state =
        agent.state
        |> Map.update!(:callback_log, &[entry | &1])
        |> Map.update(:callback_count, %{}, fn counts ->
          Map.update(counts, callback_name, 1, &(&1 + 1))
        end)

      %{agent | state: new_state}
    end

    @impl true
    def on_before_validate_state(agent) do
      {:ok, track_callback(agent, :on_before_validate_state)}
    end

    @impl true
    def on_after_validate_state(agent) do
      {:ok, track_callback(agent, :on_after_validate_state)}
    end

    @impl true
    def on_before_plan(agent, _instructions, _context) do
      agent = track_callback(agent, {:on_before_plan, nil})
      {:ok, agent}
    end

    @impl true
    def on_before_run(agent) do
      {:ok, track_callback(agent, :on_before_run)}
    end

    @impl true
    def on_after_run(agent, _result) do
      {:ok, track_callback(agent, :on_after_run)}
    end

    @impl true
    def on_after_directives(agent, _result) do
      {:ok, track_callback(agent, :on_after_directives)}
    end

    @impl true
    def on_error(agent, _error) do
      {:ok, track_callback(agent, :on_error)}
    end
  end

  defmodule CustomRunnerAgent do
    @moduledoc "Agent using a custom runner implementation"
    use Jido.Agent,
      name: "custom_runner_agent",
      runner: JidoTest.TestRunners.LoggingRunner,
      actions: [JidoTest.TestActions.BasicAction]
  end

  defmodule DirectiveAgent do
    @moduledoc "Agent that emits directives for testing server process management"
    use Jido.Agent,
      name: "directive_agent",
      description: "Tests directive functionality",
      category: "test",
      tags: ["test", "directives"],
      vsn: "1.0.0",
      actions: [
        Jido.Actions.Directives.EnqueueAction,
        Jido.Actions.Directives.RegisterAction,
        Jido.Actions.Directives.DeregisterAction,
        Jido.Actions.Directives.Spawn,
        Jido.Actions.Directives.Kill,
        Jido.Actions.Directives.Publish,
        Jido.Actions.Directives.Subscribe,
        Jido.Actions.Directives.Unsubscribe
      ],
      schema: [
        processes: [
          type: {:list, :pid},
          default: [],
          doc: "List of spawned process PIDs"
        ]
      ]
  end
end
