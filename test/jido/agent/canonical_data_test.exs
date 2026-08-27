defmodule Jido.Agent.CanonicalDataTest do
  use ExUnit.Case, async: true

  alias Jido.Agent

  alias Jido.Agent.{Data, Extension, Plugin, PluginDefaults, Schedule}

  defmodule ExamplePlugin do
  end

  defmodule ExampleExtension do
    @behaviour Extension
  end

  test "new builds one inert canonical Agent definition" do
    assert {:ok, agent} =
             Agent.new(
               name: "support_agent",
               description: "Routes support work",
               metadata: %{owner: "support"}
             )

    assert %Agent{
             id: nil,
             state: nil,
             agent_module: nil,
             name: "support_agent",
             description: "Routes support work",
             state_schema: [],
             plugin_defaults: %PluginDefaults{mode: :inherit, overrides: %{}},
             plugins: [],
             routes: [],
             schedules: [],
             extensions: [],
             metadata: %{owner: "support"}
           } = agent

    fields = agent |> Map.from_struct() |> Map.keys()
    refute :strategy in fields
    refute :category in fields
    refute :tags in fields
    refute :vsn in fields
    refute :schema in fields
  end

  test "nested constructors normalize maps and keyword lists" do
    plugin =
      Plugin.new!(
        module: ExamplePlugin,
        as: :search,
        config: %{limit: 10},
        metadata: %{source: "test"}
      )

    defaults =
      PluginDefaults.new!(
        mode: :none,
        overrides: %{search: plugin, removed: :disabled}
      )

    schedule =
      Schedule.new!(%{
        name: "heartbeat",
        cron_expression: "*/5 * * * *",
        signal_type: "agent.heartbeat",
        data: %{count: 1},
        metadata: %{"source" => "test"}
      })

    extension =
      Extension.Declaration.new!(
        module: ExampleExtension,
        data: %{enabled: true},
        metadata: %{owner: :agent}
      )

    assert plugin == Plugin.new!(plugin)
    assert defaults == PluginDefaults.new!(defaults)
    assert schedule == Schedule.new!(schedule)
    assert extension == Extension.Declaration.new!(extension)

    assert {:ok, agent} =
             Agent.new(%{
               name: "normalized_agent",
               plugin_defaults: %{mode: :none, overrides: %{search: Map.from_struct(plugin)}},
               plugins: [Map.from_struct(plugin)],
               routes: [{"agent.heartbeat", ExamplePlugin, %{source: "agent"}}],
               schedules: [Map.from_struct(schedule)],
               extensions: [Map.from_struct(extension)]
             })

    assert agent.plugin_defaults.overrides.search == plugin
    assert agent.plugins == [plugin]

    assert [
             %Jido.Signal.Router.Route{
               path: "agent.heartbeat",
               target: {ExamplePlugin, %{source: "agent"}}
             }
           ] = agent.routes

    assert agent.schedules == [schedule]
    assert agent.extensions == [extension]
  end

  test "portable Agent data accepts scalars, named MFA tuples, lists, and supported maps" do
    value = %{
      "string" => nil,
      0 => [true, 1, 1.5, "text", :existing_atom],
      key: {String, :trim, []}
    }

    assert :ok = Data.validate(value)
    assert :ok = Data.validate_object(value)
  end

  test "portable Agent data rejects unsafe values, invalid UTF-8, and unsupported keys" do
    assert {:error, _error} = Data.validate_object([])
    assert {:error, _error} = Data.validate([:ok | :tail])
    assert {:error, _error} = Data.validate(<<255>>)

    for value <- [{:tuple}, fn -> :ok end, self(), make_ref(), %URI{} | Port.list()] do
      assert {:error, error} = Data.validate(value)
      assert Exception.message(error) == "agent data contains an unsupported value"
    end

    for key <- [-1, nil, {:tuple}] do
      assert {:error, error} = Data.validate(%{key => :value})
      assert Exception.message(error) == "agent data contains an unsupported map key"
    end
  end
end
