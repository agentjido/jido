defmodule Jido.Agent.RegistryTest do
  use ExUnit.Case, async: false

  alias Jido.Agent
  alias Jido.Agent.{Plugin, Registry, Schedule}
  alias Jido.Error.ValidationError

  defmodule RouteAction do
    use Jido.Action,
      name: "registry_route_action",
      schema: Zoi.object(%{value: Zoi.integer() |> Zoi.optional()}),
      output_schema: Zoi.object(%{value: Zoi.integer() |> Zoi.optional()})

    @impl true
    def run(params, _context) do
      Process.put(:registry_action_ran, true)
      {:ok, params}
    end
  end

  defmodule PluginOnlyAction do
    use Jido.Action, name: "registry_plugin_only_action", schema: []

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule RegistryPlugin do
    use Jido.Plugin,
      name: "registry_plugin",
      state_key: :registry_plugin,
      actions: [PluginOnlyAction]

    @impl true
    def mount(_agent, _config) do
      Process.put(:registry_plugin_mounted, true)
      {:ok, %{}}
    end
  end

  defmodule RegistryExtension do
    @behaviour Jido.Agent.Extension

    @impl true
    def validate_executable(_data), do: :ok

    @impl true
    def registry_values(data) do
      Process.put(:registry_extension_values_called, true)
      [{:data, data}]
    end

    @impl true
    def compile(_data, _context) do
      Process.put(:registry_extension_compiled, true)
      {:ok, %{}}
    end
  end

  defmodule RouteMatches do
    def selected?(_signal), do: true
  end

  setup do
    Process.delete(:registry_action_ran)
    Process.delete(:registry_plugin_mounted)
    Process.delete(:registry_extension_values_called)
    Process.delete(:registry_extension_compiled)
    :ok
  end

  test "Registry resolves every core kind and one namespaced extension kind" do
    match = &RouteMatches.selected?/1
    schema = Zoi.object(%{count: Zoi.integer()})
    extension_kind = {:extension, RegistryExtension, :binding}
    binding = %{provider: :test}

    registry =
      Registry.new!(%{
        "plugins/main" => {:plugin, RegistryPlugin},
        "actions/run" => {:action, RouteAction},
        "schemas/state" => {:schema, schema},
        "route-matches/selected" => {:route_match, match},
        "extensions/main" => {:extension, RegistryExtension},
        "atoms/ready" => {:atom, :ready},
        "extension-values/binding" => {extension_kind, binding}
      })

    assert {:ok, RegistryPlugin} = Registry.resolve(registry, "plugins/main", :plugin)
    assert {:ok, RouteAction} = Registry.resolve(registry, "actions/run", :action)
    assert {:ok, ^schema} = Registry.resolve(registry, "schemas/state", :schema)

    assert {:ok, ^match} =
             Registry.resolve(registry, "route-matches/selected", :route_match)

    assert {:ok, RegistryExtension} =
             Registry.resolve(registry, "extensions/main", :extension)

    assert {:ok, :ready} = Registry.resolve(registry, "atoms/ready", :atom)

    assert {:ok, ^binding} =
             Registry.resolve(registry, "extension-values/binding", extension_kind)

    assert {:ok, "extension-values/binding"} =
             Registry.identifier(registry, extension_kind, binding)

    assert {:error, %ValidationError{}} =
             Registry.resolve(registry, "actions/run", :plugin)

    assert {:error, %ValidationError{}} =
             Registry.resolve(registry, "actions/run", :strategy)
  end

  test "namespaced extension kinds have one strict trusted shape" do
    value = %{model: :small}

    assert {:ok, %Registry{}} =
             Registry.new(%{
               "extension-values/model" => {{:extension, RegistryExtension, :model}, value}
             })

    for kind <- [
          {:extension, "Elixir.RegistryExtension", :model},
          {:extension, RegistryExtension, "model"},
          {:extension, nil, :model},
          {:extension, RegistryExtension, nil},
          {:extension, RegistryExtension},
          {:extension, RegistryExtension, :model, :extra}
        ] do
      assert {:error, %ValidationError{}} =
               Registry.new(%{"extension-values/model" => {kind, value}})
    end

    assert {:error, %ValidationError{}} =
             Registry.new(%{"strategies/direct" => {:strategy, String}})
  end

  test "Registry enforces the Flow identifier grammar and byte limit" do
    for identifier <- [
          "a",
          "Agent_1/routes.main:@v-1",
          String.duplicate("a", 255)
        ] do
      assert {:ok, registry} = Registry.new(%{identifier => {:schema, identifier}})
      assert {:ok, ^identifier} = Registry.resolve(registry, identifier, :schema)
    end

    for identifier <- [
          nil,
          "",
          "-leading",
          "bad space",
          "bad?character",
          "módule",
          String.duplicate("a", 256)
        ] do
      assert {:error, %ValidationError{}} =
               Registry.new(%{identifier => {:schema, :value}})
    end
  end

  test "Registry limits entries and rejects duplicate write values" do
    entries = Map.new(1..10_001, &{"schemas/#{&1}", {:schema, &1}})

    assert {:error, %ValidationError{}} = Registry.new(entries)

    assert {:error, %ValidationError{}} =
             Registry.new(%{
               "actions/one" => {:action, RouteAction},
               "actions/two" => {:action, RouteAction}
             })

    assert_raise ValidationError, fn -> apply(Registry, :new!, [:invalid]) end
  end

  test "aliases are direct read names and canonical writes use only the write ID" do
    registry =
      Registry.new!(%{
        "actions/current" => {:action, RouteAction},
        "actions/old" => {:alias, "actions/current"}
      })

    assert {:ok, RouteAction} = Registry.resolve(registry, "actions/old", :action)
    assert {:ok, "actions/current"} = Registry.identifier(registry, :action, RouteAction)
    assert {:ok, ^registry} = Registry.new(registry)

    assert {:error, %ValidationError{}} =
             Registry.new(%{
               "actions/current" => {:action, RouteAction},
               "actions/old" => {:alias, "actions/older"},
               "actions/older" => {:alias, "actions/current"}
             })

    assert {:error, %ValidationError{}} =
             Registry.new(%{"actions/old" => {:alias, "actions/missing"}})
  end

  test "resolve defends against malformed alias state" do
    alias_chain = %Registry{
      entries: %{
        "actions/old" => {:alias, "actions/new"},
        "actions/new" => {:alias, "actions/current"},
        "actions/current" => {:action, RouteAction}
      },
      write_ids: %{}
    }

    missing_target = %Registry{
      entries: %{"actions/old" => {:alias, "actions/missing"}},
      write_ids: %{}
    }

    assert {:error, %ValidationError{}} =
             Registry.resolve(alias_chain, "actions/old", :action)

    assert {:error, %ValidationError{}} =
             Registry.resolve(missing_target, "actions/old", :action)
  end

  test "from_agent derives deterministic IDs from authored Agent data only" do
    state_schema =
      Zoi.object(%{
        count: Zoi.integer() |> Zoi.default(0)
      })

    agent =
      Agent.new!(
        name: "registry_agent",
        state_schema: state_schema,
        plugin_defaults: :none,
        plugins: [
          Plugin.new!(
            module: RegistryPlugin,
            as: :plugin_alias,
            config: %{config_key: :config_value},
            metadata: %{plugin_meta_key: :plugin_meta_value}
          )
        ],
        routes: [
          {"registry.selected", &RouteMatches.selected?/1, RouteAction,
           %{route_param_key: :route_param_value}, 10},
          {"registry.tick", RouteAction}
        ],
        schedules: [
          Schedule.new!(
            name: "tick",
            cron_expression: "*/5 * * * *",
            signal_type: "registry.tick",
            data: %{schedule_data_key: :schedule_data_value},
            metadata: %{schedule_meta_key: :schedule_meta_value}
          )
        ],
        extensions: [
          %{
            module: RegistryExtension,
            data: %{extension_data_key: :extension_data_value},
            metadata: %{extension_meta_key: :extension_meta_value}
          }
        ],
        metadata: %{
          root_meta_key: :root_meta_value,
          callback: {RouteMatches, :selected?, [:callback_argument]}
        }
      )

    assert {:ok, registry} = Registry.from_agent(agent)
    assert {:ok, ^registry} = Registry.from_agent(agent)
    assert {:ok, ^state_schema} = Registry.resolve(registry, "schemas/generated-1", :schema)
    assert {:ok, _identifier} = Registry.identifier(registry, :plugin, RegistryPlugin)
    assert {:ok, _identifier} = Registry.identifier(registry, :action, RouteAction)

    assert {:ok, _identifier} =
             Registry.identifier(registry, :route_match, &RouteMatches.selected?/1)

    assert {:ok, _identifier} = Registry.identifier(registry, :extension, RegistryExtension)

    for atom <- [
          :plugin_alias,
          :config_key,
          :config_value,
          :plugin_meta_key,
          :plugin_meta_value,
          :route_param_key,
          :route_param_value,
          :schedule_data_key,
          :schedule_data_value,
          :schedule_meta_key,
          :schedule_meta_value,
          :extension_meta_key,
          :extension_meta_value,
          :root_meta_key,
          :root_meta_value,
          :callback,
          RouteMatches,
          :selected?,
          :callback_argument
        ] do
      assert {:ok, _identifier} = Registry.identifier(registry, :atom, atom)
    end

    assert {:ok, _identifier} =
             Registry.identifier(
               registry,
               {:extension, RegistryExtension, :data},
               %{extension_data_key: :extension_data_value}
             )

    assert {:error, %ValidationError{}} =
             Registry.identifier(registry, :action, PluginOnlyAction)

    assert {:error, %ValidationError{}} =
             Registry.identifier(registry, :atom, RegistryPlugin)

    refute Process.get(:registry_action_ran)
    refute Process.get(:registry_plugin_mounted)
    assert Process.get(:registry_extension_values_called)
    refute Process.get(:registry_extension_compiled)
  end

  test "from_agent requires an executable Agent and Registry data does not affect identity" do
    agent =
      Agent.new!(
        name: "identity_registry_agent",
        plugin_defaults: :none,
        routes: [{"registry.run", RouteAction}]
      )

    assert {:ok, identity} = Agent.semantic_identity(agent)
    assert {:ok, _registry} = Registry.from_agent(agent)
    assert {:ok, ^identity} = Agent.semantic_identity(agent)

    Registry.new!(%{
      "actions/current" => {:action, RouteAction},
      "actions/old" => {:alias, "actions/current"}
    })

    assert {:ok, ^identity} = Agent.semantic_identity(agent)
    assert {:error, %ValidationError{}} = Registry.from_agent(:invalid)

    invalid =
      Agent.new!(
        name: "invalid_executable_registry_agent",
        plugin_defaults: :none,
        routes: [{"registry.invalid", String}]
      )

    assert {:error, %ValidationError{}} = Registry.from_agent(invalid)
  end

  test "unknown identifier text does not create atoms or module names" do
    registry = Registry.new!(%{"actions/run" => {:action, RouteAction}})

    for index <- 1..500 do
      identifier = "Unknown.Registry.Module.Warmup.#{index}"

      assert {:error, %ValidationError{}} =
               Registry.resolve(registry, identifier, :action)
    end

    before_count = :erlang.system_info(:atom_count)

    for index <- 1..500 do
      identifier = "Unknown.Registry.Module.Repeated.#{index}"

      assert {:error, %ValidationError{}} =
               Registry.resolve(registry, identifier, :action)
    end

    atom_count_growth = :erlang.system_info(:atom_count) - before_count

    # Error formatting can load a small fixed set of existing modules. If the
    # 500 unique text values became atoms, this increase would be at least 500.
    assert atom_count_growth < 50
  end
end
