defmodule JidoTest.TestSkills do
  @moduledoc false

  defmodule TestSkill do
    @moduledoc false
    use Jido.Skill,
      name: "test_skill",
      description: "Test skill for callback testing",
      opts_key: :test_skill,
      signal_patterns: [
        "test.skill.**"
      ]

    def handle_signal(signal, _skill) do
      {:ok, %{signal | data: Map.put(signal.data, :skill_handled, true)}}
    end

    def transform_result(_signal, result, _skill) do
      {:ok, Map.put(result, :skill_processed, true)}
    end
  end

  defmodule WeatherMonitorSkill do
    @moduledoc false
    use Jido.Skill,
      name: "weather_monitor",
      description: "Extends agent with weather monitoring capabilities",
      category: "monitoring",
      tags: ["weather", "alerts", "monitoring"],
      vsn: "1.0.0",
      opts_key: :weather,
      signal_patterns: [
        "weather_monitor.**"
      ],
      opts_schema: [
        weather_api: [
          type: :map,
          required: true,
          doc: "Weather API configuration"
        ],
        alerts: [
          type: :map,
          required: false,
          doc: "Alert configuration"
        ]
      ]

    # Actions that this skill provides to the agent
    defmodule Actions do
      @moduledoc false
      defmodule ProcessWeatherData do
        @moduledoc false
        use Jido.Action,
          name: "process_weather_data",
          description: "Processes incoming weather data",
          schema: [
            signal: [type: :map, required: true]
          ]

        def run(%{signal: signal}, context) do
          # We can access secrets from context
          _api_key = get_in(context, [:secrets, :weather_api_key])

          # We can access agent state using our keyspace
          current_state = get_in(context, [:state, :weather, :current_conditions])

          with {:ok, processed_data} <- validate_weather_data(signal.data),
               {:ok, enriched_data} <- enrich_weather_data(processed_data, current_state) do
            {:ok,
             %{
               weather_data: enriched_data,
               timestamp: DateTime.utc_now()
             }}
          end
        end

        # Mock validation function
        defp validate_weather_data(data) do
          # In a real implementation this would validate the data structure
          {:ok,
           %{
             temperature: data[:temperature] || 72.5,
             humidity: data[:humidity] || 45,
             wind_speed: data[:wind_speed] || 5.5,
             conditions: data[:conditions] || "partly_cloudy"
           }}
        end

        # Mock enrichment function
        defp enrich_weather_data(processed_data, current_state) do
          # In a real implementation this would add derived/computed fields
          enriched =
            Map.merge(processed_data, %{
              feels_like: processed_data.temperature + 2,
              trend: if(current_state, do: "rising", else: "stable"),
              alerts: []
            })

          {:ok, enriched}
        end
      end

      defmodule GenerateWeatherAlert do
        @moduledoc false
        use Jido.Action,
          name: "generate_weather_alert",
          schema: [
            signal: [type: :map, required: true]
          ]

        def run(%{signal: signal}, context) do
          webhook_url = get_in(context, [:secrets, :alert_webhook_url])
          alert_history = get_in(context, [:state, :weather, :alert_history])

          conditions = evaluate_alert_conditions(signal.data)

          if should_generate_alert?(conditions, alert_history) do
            {:ok,
             %{
               alert: true,
               conditions: conditions,
               severity: calculate_alert_severity(conditions),
               webhook_url: webhook_url,
               generated_at: DateTime.utc_now()
             }}
          else
            {:ok, :no_alert_needed}
          end
        end

        # Mock evaluation function
        defp evaluate_alert_conditions(data) do
          # In real implementation would evaluate weather conditions for alerts
          %{
            high_wind: data[:wind_speed] && data[:wind_speed] > 20,
            extreme_temp:
              data[:temperature] && (data[:temperature] > 95 || data[:temperature] < 32),
            severe_weather: data[:conditions] in ["thunderstorm", "tornado", "hurricane"]
          }
        end

        # Mock alert check
        defp should_generate_alert?(conditions, history) do
          # Check if any condition is true and not in recent history
          Enum.any?(conditions, fn {_k, v} -> v end) && length(history || []) < 5
        end

        # Mock severity calculator
        defp calculate_alert_severity(conditions) do
          cond do
            conditions.severe_weather -> 5
            conditions.extreme_temp -> 4
            conditions.high_wind -> 3
            true -> 1
          end
        end
      end
    end

    # Define processes (sensors) that this skill requires
    def child_spec(config) do
      [
        {Jido.Sensors.WeatherAPI,
         [
           name: "weather_api",
           config: config.weather_api,
           interval: config.fetch_interval || :timer.minutes(15),
           locations: config.locations
         ]},
        {Jido.Sensors.WeatherAlerts,
         [
           name: "weather_alerts",
           config: config.alerts,
           sources: config.alert_sources || [:noaa, :weather_underground]
         ]}
      ]
    end

    @doc """
    Skill: Weather Monitor
    Signal Contracts:
    - Incoming:
      * weather_monitor.data.received: Raw weather data from sensors
      * weather_monitor.alert.**: Weather alerts from alert sensors
    - Outgoing:
      * weather_monitor.report.generated: Processed weather reports
      * weather_monitor.alert.processed: Processed alert notifications
    """
    def router do
      [
        # High priority weather alerts
        %{
          path: "weather_monitor.alert.**",
          instruction: %{
            action: Actions.GenerateWeatherAlert
          },
          priority: 100
        },

        # Process incoming weather data
        %{
          path: "weather_monitor.data.received",
          instruction: %{
            action: Actions.ProcessWeatherData
          },
          priority: 50
        },

        # Handle severe conditions with pattern matching
        %{
          path: "weather_monitor.condition.*",
          match: fn signal ->
            get_in(signal, [:data, :severity]) >= 3
          end,
          instruction: %{
            action: Actions.GenerateWeatherAlert
          },
          priority: 75
        }
      ]
    end

    def handle_result(
          {:ok, %{weather_data: data}},
          "weather_monitor.data.received"
        ) do
      [
        %Signal{
          id: Jido.Util.generate_id(),
          source: "replace_agent_id",
          type: "weather_monitor.data.processed",
          data: data
        }
      ]
    end

    def handle_result(
          {:ok, %{alert: true} = alert_data},
          "weather_monitor.alert.**"
        ) do
      [
        %Signal{
          id: Jido.Util.generate_id(),
          source: "replace_agent_id",
          type: "weather_monitor.alert.generated",
          data: Map.take(alert_data, [:conditions, :severity, :generated_at])
        }
      ]
    end

    def handle_result(
          {:ok, :no_alert_needed},
          "weather_monitor.alert.**"
        ) do
      # No signals emitted when no alert is needed
      []
    end

    # Add handle_signal and transform_result callbacks
    def handle_signal(signal, _skill) do
      {:ok, %{signal | data: Map.put(signal.data, :skill_handled, true)}}
    end

    def transform_result(_signal, result, _skill) do
      {:ok, Map.put(result, :skill_processed, true)}
    end
  end

  # Mock skill for testing
  defmodule MockSkill do
    @moduledoc """
    A basic mock skill for testing.
    """
    use Jido.Skill,
      name: "mock_skill",
      description: "Basic mock skill for testing",
      opts_key: :mock_skill,
      signal_patterns: [
        "test.path.*"
      ]

    @impl true
    def router(_opts \\ []) do
      [
        %Jido.Signal.Router.Route{
          path: "test.path",
          target: %Jido.Instruction{action: :test_handler},
          priority: 0
        }
      ]
    end

    @impl true
    def child_spec(_opts \\ []) do
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, []},
        type: :worker
      }
    end
  end

  # Mock skill with router function
  defmodule MockSkillWithRouter do
    @moduledoc """
    A mock skill with a router function.
    """
    use Jido.Skill,
      name: "mock_skill_with_router",
      description: "Mock skill with router function",
      opts_key: :mock_skill_with_router,
      signal_patterns: [
        "test.path.*"
      ]

    @impl true
    def router(_opts \\ []) do
      [
        %Jido.Signal.Router.Route{
          path: "test.path",
          target: %Jido.Instruction{action: :test_handler},
          priority: 0
        }
      ]
    end

    @impl true
    def child_spec(_opts), do: []
  end

  # Mock skill with invalid router
  defmodule InvalidRouterSkill do
    @moduledoc """
    A mock skill with an invalid router.
    """
    use Jido.Skill,
      name: "invalid_router_skill",
      description: "Mock skill with invalid router",
      opts_key: :invalid_router_skill,
      signal_patterns: [
        "test.path.*"
      ]

    @impl true
    def router(_opts \\ []) do
      :not_a_list
    end

    @impl true
    def child_spec(_opts), do: []
  end

  # Mock skill with validation schema
  defmodule MockSkillWithSchema do
    @moduledoc """
    A mock skill with a validation schema.
    """
    use Jido.Skill,
      name: "mock_skill_with_schema",
      description: "Mock skill with validation schema",
      opts_key: :mock_skill_with_schema,
      signal_patterns: [
        "test.path.*"
      ],
      opts_schema: [
        api_key: [
          type: :string,
          required: true,
          doc: "API key for the service"
        ],
        timeout: [
          type: :integer,
          default: 5000,
          doc: "Timeout in milliseconds"
        ]
      ]

    @impl true
    def router(_opts \\ []) do
      [
        %Jido.Signal.Router.Route{
          path: "test.path",
          target: %Jido.Instruction{action: :test_handler},
          priority: 0
        }
      ]
    end

    @impl true
    def child_spec(_opts \\ []) do
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, []},
        type: :worker
      }
    end
  end

  # Mock skill with custom mount implementation
  defmodule MockSkillWithMount do
    @moduledoc """
    A mock skill with a custom mount implementation that registers a custom action module.
    """
    use Jido.Skill,
      name: "mock_skill_with_mount",
      description: "Mock skill with custom mount implementation",
      opts_key: :mock_skill_with_mount,
      signal_patterns: [
        "test.path.*"
      ],
      opts_schema: []

    @impl true
    def router(_opts \\ []) do
      [
        %Jido.Signal.Router.Route{
          path: "test.path",
          target: %Jido.Instruction{action: :test_handler},
          priority: 0
        }
      ]
    end

    @impl true
    def child_spec(_opts \\ []) do
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, []},
        type: :worker
      }
    end

    @impl true
    def mount(agent, _opts) do
      # Register an existing action from JidoTest.TestActions
      {:ok, updated_agent} = Jido.Agent.register_action(agent, JidoTest.TestActions.BasicAction)

      # Update the agent state to verify the mount was called
      updated_agent =
        Map.update!(updated_agent, :state, fn state ->
          Map.put(state, :mount_called, true)
        end)

      {:ok, updated_agent}
    end
  end
end
