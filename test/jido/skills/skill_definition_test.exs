defmodule Jido.SkillDefinitionTest do
  use ExUnit.Case, async: true
  alias JidoTest.TestSkills.WeatherMonitorSkill
  alias Jido.Runner.Result
  alias Jido.Signal

  @moduletag :capture_log

  describe "skill definition" do
    test "defines a skill with valid configuration" do
      assert WeatherMonitorSkill.name() == "weather_monitor"

      assert WeatherMonitorSkill.description() ==
               "Extends agent with weather monitoring capabilities"

      assert WeatherMonitorSkill.category() == "monitoring"
      assert WeatherMonitorSkill.tags() == ["weather", "alerts", "monitoring"]
      assert WeatherMonitorSkill.vsn() == "1.0.0"
      assert WeatherMonitorSkill.schema_key() == :weather
    end

    test "skill metadata is accessible" do
      metadata = WeatherMonitorSkill.__skill_metadata__()

      assert metadata.name == "weather_monitor"
      assert metadata.description == "Extends agent with weather monitoring capabilities"
      assert metadata.category == "monitoring"
      assert metadata.tags == ["weather", "alerts", "monitoring"]
      assert metadata.vsn == "1.0.0"
      assert metadata.schema_key == :weather

      assert metadata.signals == %{
               input: [
                 "weather_monitor.data.received",
                 "weather_monitor.alert.triggered",
                 "weather_monitor.conditions.updated"
               ],
               output: [
                 "weather_monitor.alert.generated",
                 "weather_monitor.data.processed",
                 "weather_monitor.conditions.changed"
               ]
             }

      assert metadata.config_schema == %{
               weather_api: [type: :map, required: true, doc: "Weather API configuration"],
               alerts: [type: :map, required: false, doc: "Alert configuration"]
             }
    end

    test "skill can be serialized to JSON" do
      json = WeatherMonitorSkill.to_json()

      assert json.name == "weather_monitor"
      assert json.description == "Extends agent with weather monitoring capabilities"
      assert json.category == "monitoring"
      assert json.tags == ["weather", "alerts", "monitoring"]
      assert json.vsn == "1.0.0"
      assert json.schema_key == :weather
    end

    test "skill defines valid signal patterns" do
      signals = WeatherMonitorSkill.signals()

      assert signals.input == [
               "weather_monitor.data.received",
               "weather_monitor.alert.triggered",
               "weather_monitor.conditions.updated"
             ]

      assert signals.output == [
               "weather_monitor.alert.generated",
               "weather_monitor.data.processed",
               "weather_monitor.conditions.changed"
             ]
    end

    test "skill defines initial state" do
      initial_state = WeatherMonitorSkill.initial_state()

      assert initial_state == %{
               current_conditions: nil,
               alert_history: [],
               last_report: nil,
               locations: ["NYC", "LA", "CHI"]
             }
    end

    test "skill defines child specs" do
      config = %{
        weather_api: %{api_key: "test"},
        fetch_interval: 900_000,
        locations: ["TEST"],
        alerts: %{enabled: true},
        alert_sources: [:noaa]
      }

      child_specs = WeatherMonitorSkill.child_spec(config)
      assert is_list(child_specs)
      assert length(child_specs) == 2
    end

    test "skill defines router" do
      routes = WeatherMonitorSkill.router()

      assert is_list(routes)
      assert length(routes) == 3

      alert_route = Enum.find(routes, &(&1.path == "weather_monitor.alert.**"))
      assert alert_route.priority == 100
      assert alert_route.instruction.action == WeatherMonitorSkill.Actions.GenerateWeatherAlert
    end

    test "skills cannot be defined at runtime" do
      assert {:error, error} = Jido.Skill.new()
      assert error.type == :config_error
      assert error.message == "Skills should not be defined at runtime"
    end
  end

  describe "handle_result/2" do
    test "handles successful weather data processing" do
      result = %Result{
        status: :ok,
        result_state: %{
          weather_data: %{
            temperature: 75.0,
            humidity: 45,
            wind_speed: 10,
            conditions: "sunny"
          }
        }
      }

      signals = WeatherMonitorSkill.handle_result(result, "weather_monitor.data.received")
      assert length(signals) == 1
      [signal] = signals
      assert signal.type == "weather_monitor.data.processed"
      assert signal.data == result.result_state.weather_data
    end

    test "handles weather alert generation" do
      result = %Result{
        status: :ok,
        result_state: %{
          alert: true,
          conditions: %{severe_weather: true},
          severity: 5,
          generated_at: ~U[2024-01-01 12:00:00Z]
        }
      }

      signals = WeatherMonitorSkill.handle_result(result, "weather_monitor.alert.**")
      assert length(signals) == 1
      [signal] = signals
      assert signal.type == "weather_monitor.alert.generated"
      assert Map.has_key?(signal.data, :conditions)
      assert Map.has_key?(signal.data, :severity)
      assert Map.has_key?(signal.data, :generated_at)
    end

    test "handles no alert needed case" do
      result = %Result{
        status: :ok,
        result_state: :no_alert_needed
      }

      signals = WeatherMonitorSkill.handle_result(result, "weather_monitor.alert.**")
      assert signals == []
    end
  end
end
