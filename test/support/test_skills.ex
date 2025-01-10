defmodule JidoTest.TestSkills do
  defmodule WeatherMonitorSkill do
    use Jido.Skill,
      name: "weather_monitor",
      description: "Extends agent with weather monitoring capabilities",
      category: "monitoring",
      tags: ["weather", "alerts", "monitoring"],
      vsn: "1.0.0",
      schema_key: :weather,
      signals: %{
        # Input signals this skill handles
        input: [
          "weather_monitor.data.received",
          "weather_monitor.alert.triggered",
          "weather_monitor.conditions.updated"
        ],
        # Output signals this skill may emit
        output: [
          "weather_monitor.alert.generated",
          "weather_monitor.data.processed",
          "weather_monitor.conditions.changed"
        ]
      },
      config: %{
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
      }

    # Actions that this skill provides to the agent
    defmodule Actions do
      defmodule ProcessWeatherData do
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

    # Optional: Initial state for the skill's keyspace
    def initial_state do
      %{
        current_conditions: nil,
        alert_history: [],
        last_report: nil,
        locations: ["NYC", "LA", "CHI"]
      }
    end

    def handle_result(
          %Result{status: :ok, result_state: %{weather_data: data}} = result,
          "weather_monitor.data.received"
        ) do
      [
        %Signal{
          id: UUID.uuid4(),
          source: "replace_agent_id",
          type: "weather_monitor.data.processed",
          data: data
        }
      ]
    end

    def handle_result(
          %Result{status: :ok, result_state: %{alert: true} = alert_data},
          "weather_monitor.alert.**"
        ) do
      [
        %Signal{
          id: UUID.uuid4(),
          source: "replace_agent_id",
          type: "weather_monitor.alert.generated",
          data: Map.take(alert_data, [:conditions, :severity, :generated_at])
        }
      ]
    end

    def handle_result(
          %Result{status: :ok, result_state: :no_alert_needed},
          "weather_monitor.alert.**"
        ) do
      # No signals emitted when no alert is needed
      []
    end
  end
end
