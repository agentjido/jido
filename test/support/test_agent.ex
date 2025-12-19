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

  defmodule LoopingAgent do
    @moduledoc "Agent with looping actions for testing cascaded enqueuing"
    use Jido.Agent,
      name: "looping_agent",
      actions: [
        JidoTest.TestActions.BasicAction,
        JidoTest.TestActions.Add,
        JidoTest.TestActions.Multiply,
        JidoTest.TestActions.NoSchema,
        JidoTest.TestActions.EnqueueAction,
        JidoTest.TestActions.RegisterAction,
        JidoTest.TestActions.DeregisterAction,
        JidoTest.TestActions.LoopingAction,
        JidoTest.TestActions.CountdownAction,
        JidoTest.TestActions.IncrementWithLimit,
        Jido.Actions.Iterator,
        Jido.Actions.While
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
        JidoTest.TestActions.ContextAction,
        Jido.Tools.StateManager.Get,
        Jido.Tools.StateManager.Set,
        Jido.Tools.StateManager.Update,
        Jido.Tools.StateManager.Delete
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
    def on_after_run(agent, result, _directives) do
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
      # Convert error to map format that tests expect
      error_map = Jido.Error.to_map(result)

      new_state =
        agent.state
        |> Map.update!(:error_count, &(&1 + 1))
        |> Map.put(:last_error, error_map)

      {:ok, %{agent | state: new_state}, []}
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
    def mount(state, _opts) do
      agent = track_callback(state.agent, :mount)
      {:ok, %{state | agent: agent}}
    end

    @impl true
    def code_change(state, _old_vsn, _extra) do
      agent = track_callback(state.agent, :code_change)
      {:ok, %{state | agent: agent}}
    end

    @impl true
    def shutdown(state, _reason) do
      agent = track_callback(state.agent, :shutdown)
      {:ok, %{state | agent: agent}}
    end

    @impl true
    def handle_signal(signal, _agent) do
      {:ok, %{signal | data: Map.put(signal.data, :agent_handled, true)}}
    end

    @impl true
    def transform_result(_signal, result, _agent) do
      {:ok, Map.put(result, :agent_processed, true)}
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
    def on_after_run(agent, _result, _directives) do
      {:ok, track_callback(agent, :on_after_run)}
    end

    @impl true
    def on_error(agent, _error) do
      {:ok, track_callback(agent, :on_error)}
    end
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

  defmodule CustomServerAgent do
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

    require Logger

    @impl true
    def start_link(opts) do
      agent_id = Keyword.get(opts, :id) || Jido.Util.generate_id()
      initial_state = Keyword.get(opts, :initial_state, %{})
      agent = CustomServerAgent.new(agent_id, initial_state)

      Jido.Agent.Server.start_link(
        agent: agent,
        name: agent_id,
        routes: [
          {"example.event", Instruction.new!(action: JidoTest.TestActions.BasicAction)}
        ],
        skills: [
          JidoTest.TestSkills.WeatherMonitorSkill
        ],
        child_specs: [
          {JidoTest.TestSensors.CounterSensor, []}
        ]
      )
    end

    @impl true
    def mount(agent, opts) do
      Logger.debug("Mounting CustomServerAgent: #{inspect(agent)} #{inspect(opts)}")

      # Validate battery level is positive
      if agent.state.battery_level < 0 do
        {:error, :invalid_battery_level}
      else
        # You can modify state here if needed
        {:ok, agent}
      end
    end

    @impl true
    def shutdown(agent, reason) do
      Logger.debug("Shutting down CustomServerAgent: #{inspect(agent)} #{inspect(reason)}")

      # Validate battery level is positive
      if agent.state.battery_level < 0 do
        {:error, :invalid_battery_level}
      else
        # Clean up any resources if needed
        {:ok, agent}
      end
    end
  end

  defmodule SignalOutputAgent do
    @moduledoc false
    use Jido.Agent,
      name: "signal_output_agent",
      schema: [
        processed_results: [type: {:list, :any}, default: []]
      ]

    @impl true
    def transform_result(%Signal{type: "test.string"} = _signal, data, _agent) do
      {:ok, {:processed_string, String.upcase(data)}}
    end

    def transform_result(%Signal{type: "test.map"} = _signal, data, _agent) do
      {:ok, Map.put(data, :processed_at, DateTime.utc_now())}
    end

    def transform_result(%Signal{type: "test.error"} = signal, reason, _agent) do
      {:error, %{reason: reason, signal_id: signal.id}}
    end

    def transform_result(signal, other, _agent) do
      {:error, %{signal: signal, result: other}}
    end
  end

  defmodule TaskManagementAgent do
    @moduledoc "Agent for testing task management functionality"
    use Jido.Agent,
      name: "task_management_agent",
      description: "Tests task management functionality",
      category: "test",
      tags: ["test", "tasks"],
      vsn: "1.0.0",
      actions: [
        Jido.Tools.Tasks.Create,
        Jido.Tools.Tasks.Update,
        Jido.Tools.Tasks.Toggle,
        Jido.Tools.Tasks.Delete
      ],
      schema: [
        tasks: [
          type: :map,
          default: %{},
          doc: "List of tasks"
        ]
      ]
  end
end
