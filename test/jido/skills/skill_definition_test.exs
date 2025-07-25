defmodule Jido.SkillDefinitionTest do
  use JidoTest.Case, async: true

  alias Jido.Error
  alias JidoTest.TestSkills.WeatherMonitorSkill

  @moduletag :capture_log

  describe "skill definition" do
    test "defines a skill with valid configuration" do
      assert WeatherMonitorSkill.name() == "weather_monitor"

      assert WeatherMonitorSkill.description() ==
               "Extends agent with weather monitoring capabilities"

      assert WeatherMonitorSkill.category() == "monitoring"
      assert WeatherMonitorSkill.tags() == ["weather", "alerts", "monitoring"]
      assert WeatherMonitorSkill.vsn() == "1.0.0"
      assert WeatherMonitorSkill.opts_key() == :weather
    end

    test "skill metadata is accessible" do
      metadata = WeatherMonitorSkill.__skill_metadata__()

      assert metadata.name == "weather_monitor"
      assert metadata.description == "Extends agent with weather monitoring capabilities"
      assert metadata.category == "monitoring"
      assert metadata.tags == ["weather", "alerts", "monitoring"]
      assert metadata.vsn == "1.0.0"
      assert metadata.opts_key == :weather

      assert metadata.signal_patterns == [
               "weather_monitor.**"
             ]

      assert metadata.opts_schema == [
               weather_api: [type: :map, required: true, doc: "Weather API configuration"],
               alerts: [type: :map, required: false, doc: "Alert configuration"]
             ]
    end

    test "skill can be serialized to JSON" do
      json = WeatherMonitorSkill.to_json()

      assert json.name == "weather_monitor"
      assert json.description == "Extends agent with weather monitoring capabilities"
      assert json.category == "monitoring"
      assert json.tags == ["weather", "alerts", "monitoring"]
      assert json.vsn == "1.0.0"
      assert json.opts_key == :weather
    end

    test "skill defines valid signal patterns" do
      signal_patterns = WeatherMonitorSkill.signal_patterns()

      assert signal_patterns == [
               "weather_monitor.**"
             ]
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
      assert Error.to_map(error).type == :config_error
      assert error.message == "Skills should not be defined at runtime"
    end
  end

  describe "handle_result/2" do
    test "handles successful weather data processing" do
      result =
        {:ok,
         %{
           weather_data: %{
             temperature: 75.0,
             humidity: 45,
             wind_speed: 10,
             conditions: "sunny"
           }
         }}

      signals = WeatherMonitorSkill.handle_result(result, "weather_monitor.data.received")
      assert length(signals) == 1
      [signal] = signals
      assert signal.type == "weather_monitor.data.processed"
      assert signal.data == elem(result, 1).weather_data
    end

    test "handles weather alert generation" do
      result =
        {:ok,
         %{
           alert: true,
           conditions: %{severe_weather: true},
           severity: 5,
           generated_at: ~U[2024-01-01 12:00:00Z]
         }}

      signals = WeatherMonitorSkill.handle_result(result, "weather_monitor.alert.**")
      assert length(signals) == 1
      [signal] = signals
      assert signal.type == "weather_monitor.alert.generated"
      assert Map.has_key?(signal.data, :conditions)
      assert Map.has_key?(signal.data, :severity)
      assert Map.has_key?(signal.data, :generated_at)
    end

    test "handles no alert needed case" do
      result = {:ok, :no_alert_needed}

      signals = WeatherMonitorSkill.handle_result(result, "weather_monitor.alert.**")
      assert signals == []
    end
  end
end
