defmodule Jido.Agent.BuilderTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Builder
  alias Jido.Agent.Extension.Declaration
  alias Jido.Agent.{Plugin, PluginDefaults, Schedule}

  defmodule FirstPlugin do
  end

  defmodule SecondPlugin do
  end

  defmodule FirstExtension do
    @behaviour Jido.Agent.Extension
  end

  defmodule SecondExtension do
    @behaviour Jido.Agent.Extension
  end

  defmodule FirstTarget do
  end

  defmodule SecondTarget do
  end

  defmodule WorkSentinelPlugin do
    use Jido.Plugin,
      name: "builder_work_sentinel",
      state_key: :builder_work_sentinel,
      actions: []

    @impl true
    def mount(_agent, _config) do
      Process.put(:builder_plugin_called, true)
      {:ok, %{}}
    end
  end

  defmodule WorkSentinelExtension do
    @behaviour Jido.Agent.Extension

    @impl true
    def compile(data, _context) do
      Process.put(:builder_extension_called, true)
      {:ok, data}
    end
  end

  test "build output equals direct canonical construction" do
    expected =
      Agent.new!(
        name: "support_agent",
        description: "Routes support work",
        state_schema: [],
        plugin_defaults: %{mode: :none},
        metadata: %{owner: "support"},
        plugins: [
          %{module: FirstPlugin, as: :search, config: %{limit: 10}}
        ],
        routes: [
          {"support.requested", FirstTarget, %{source: "builder"}, 12}
        ],
        schedules: [
          %{
            name: "heartbeat",
            cron_expression: "*/5 * * * *",
            signal_type: "agent.heartbeat",
            data: %{count: 1}
          }
        ],
        extensions: [
          %{module: FirstExtension, data: %{enabled: true}}
        ]
      )

    actual =
      Builder.new("support_agent")
      |> Builder.description("Routes support work")
      |> Builder.state_schema([])
      |> Builder.plugin_defaults(mode: :none)
      |> Builder.metadata(%{owner: "support"})
      |> Builder.plugin(FirstPlugin, as: :search, config: %{limit: 10})
      |> Builder.route("support.requested", FirstTarget,
        params: %{source: "builder"},
        priority: 12
      )
      |> Builder.schedule("heartbeat", "*/5 * * * *", "agent.heartbeat", data: %{count: 1})
      |> Builder.extension(FirstExtension, %{enabled: true})
      |> Builder.build!()

    assert actual == expected
  end

  test "full root data accepts canonical structs, maps, and keyword lists" do
    plugin = Plugin.new!(module: FirstPlugin, as: :first)

    route =
      Agent.new!(name: "route_source", routes: [{"event.received", FirstTarget}]).routes
      |> List.first()

    schedule =
      Schedule.new!(
        name: "heartbeat",
        cron_expression: "*/5 * * * *",
        signal_type: "agent.heartbeat"
      )

    extension = Declaration.new!(module: FirstExtension, data: %{enabled: true})

    attrs = [
      name: "full_agent",
      plugin_defaults: PluginDefaults.new!(:none),
      plugins: [plugin, [module: SecondPlugin, as: :second]],
      routes: [route, [path: "event.finished", target: SecondTarget]],
      schedules: [schedule, schedule_attrs("cleanup")],
      extensions: [extension, [module: SecondExtension, data: %{mode: :safe}]]
    ]

    direct_attrs =
      Keyword.put(attrs, :routes, [route, {"event.finished", SecondTarget}])

    assert Builder.new(attrs) |> Builder.build!() == Agent.new!(direct_attrs)
  end

  test "build preserves the authored order of all repeated declarations" do
    agent =
      Builder.new("ordered_agent")
      |> Builder.plugin(FirstPlugin)
      |> Builder.plugin(SecondPlugin)
      |> Builder.route("event.first", FirstTarget)
      |> Builder.route("event.second", SecondTarget)
      |> Builder.schedule(schedule_attrs("first"))
      |> Builder.schedule(schedule_attrs("second"))
      |> Builder.extension(FirstExtension)
      |> Builder.extension(SecondExtension)
      |> Builder.build!()

    assert Enum.map(agent.plugins, & &1.module) == [FirstPlugin, SecondPlugin]
    assert Enum.map(agent.routes, & &1.path) == ["event.first", "event.second"]
    assert Enum.map(agent.schedules, & &1.name) == ["first", "second"]
    assert Enum.map(agent.extensions, & &1.module) == [FirstExtension, SecondExtension]
  end

  test "the first error is sticky across later valid and invalid calls" do
    builder = Builder.new("sticky_agent") |> Builder.plugin(nil)
    assert {:error, first_error} = Builder.build(builder)

    later =
      builder
      |> Builder.description("This value is valid")
      |> Builder.route("bad..path", FirstTarget)
      |> Builder.schedule(%{})
      |> Builder.extension(FirstExtension)

    assert {:error, ^first_error} = Builder.build(later)

    assert_raise first_error.__struct__, Exception.message(first_error), fn ->
      Builder.build!(later)
    end
  end

  test "new rejects unsupported forms, duplicate fields, and unknown fields" do
    invalid_inputs = [
      :invalid,
      [name: "first", name: "second"],
      [name: "unknown_agent", unknown: true],
      %{name: "strategy_agent", strategy: Jido.Agent.Strategy.Direct}
    ]

    for input <- invalid_inputs do
      assert {:error, error} = input |> Builder.new() |> Builder.build()
      assert is_exception(error)
    end
  end

  test "add options must be unique keyword lists with known fields" do
    invalid_builders = [
      Builder.new("duplicate_options")
      |> Builder.plugin(FirstPlugin, as: :first, as: :second),
      Builder.new("unknown_options")
      |> Builder.schedule("heartbeat", "* * * * *", "agent.heartbeat", unknown: true),
      Builder.new("invalid_options")
      |> Builder.route("event.received", FirstTarget, %{}),
      Builder.new("non_keyword_options")
      |> Builder.plugin(FirstPlugin, [:invalid]),
      Builder.new("unknown_extension_options")
      |> Builder.extension(FirstExtension, unknown: true),
      Builder.new("duplicate_fields")
      |> Builder.plugin([module: FirstPlugin, as: :first], as: :second)
    ]

    for builder <- invalid_builders do
      assert {:error, error} = Builder.build(builder)
      assert is_exception(error)
    end
  end

  test "Builder rejects runtime fields and has no runtime or strategy API" do
    for field <- [:id, :state, :agent_module] do
      attrs = %{field => :forbidden, name: "runtime_agent"}
      assert {:error, error} = attrs |> Builder.new() |> Builder.build()

      assert Exception.message(error) =~ "runtime"
    end

    functions = Builder.__info__(:functions)

    for function <- [:id, :state, :agent_module, :strategy, :compile, :instantiate, :start_link] do
      refute Enum.any?(functions, fn {name, _arity} -> name == function end)
    end
  end

  test "Builder creates an inert definition without plugin or extension work" do
    agent =
      Builder.new("inert_agent")
      |> Builder.plugin(WorkSentinelPlugin)
      |> Builder.extension(WorkSentinelExtension)
      |> Builder.build!()

    assert %Agent{id: nil, state: nil, agent_module: nil} = agent
    refute Map.has_key?(Map.from_struct(agent), :strategy)
    refute Process.get(:builder_plugin_called)
    refute Process.get(:builder_extension_called)
  end

  test "Builder declares its state as opaque" do
    assert {:ok, types} = Code.Typespec.fetch_types(Builder)
    assert Enum.any?(types, &match?({:opaque, {:t, _, []}}, &1))
  end

  defp schedule_attrs(name) do
    [
      name: name,
      cron_expression: "0 * * * *",
      signal_type: "agent.#{name}"
    ]
  end
end
