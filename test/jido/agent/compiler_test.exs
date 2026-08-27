defmodule Jido.Agent.CompilerTest do
  use ExUnit.Case, async: false

  alias Jido.Agent
  alias Jido.Agent.{Compiled, Plugin, PluginDefaults, Schedule}
  alias Jido.Signal.Router.Route

  defmodule CompileAction do
    use Jido.Action,
      name: "compile_action",
      schema: Zoi.object(%{value: Zoi.integer() |> Zoi.optional()}),
      output_schema: Zoi.object(%{value: Zoi.integer() |> Zoi.optional()})

    @impl true
    def run(params, _context) do
      Process.put(:compiler_action_ran, true)
      {:ok, params}
    end
  end

  defmodule CompilePlugin do
    use Jido.Plugin,
      name: "compile_plugin",
      state_key: :compile_plugin,
      actions: [CompileAction],
      capabilities: [:compile_test],
      schema: Zoi.object(%{enabled: Zoi.boolean() |> Zoi.default(true)}),
      config_schema: Zoi.object(%{limit: Zoi.integer() |> Zoi.default(5)}),
      signal_routes: [{"run", CompileAction}],
      schedules: [{"*/5 * * * *", CompileAction}],
      singleton: true

    @impl true
    def mount(_agent, _config) do
      Process.put(:compiler_plugin_mounted, true)
      {:ok, %{mounted: true}}
    end
  end

  defmodule HostDefaultPlugin do
    use Jido.Plugin,
      name: "host_default",
      state_key: :__host_default__,
      actions: [CompileAction],
      schema: Zoi.object(%{ready: Zoi.boolean() |> Zoi.default(true)}),
      config_schema: Zoi.object(%{value: Zoi.integer() |> Zoi.default(1)}),
      singleton: true
  end

  defmodule CallbackSentinelPlugin do
    use Jido.Plugin,
      name: "callback_sentinel",
      state_key: :callback_sentinel,
      actions: []

    @impl true
    def signal_routes(_config) do
      test_process = self()
      spawned = spawn(fn -> send(test_process, :compiler_process_sentinel) end)
      send(test_process, {:compiler_callback_sentinel, spawned})
      []
    end
  end

  defmodule EnvironmentSentinelPlugin do
    use Jido.Plugin,
      name: "environment_sentinel",
      state_key: :environment_sentinel,
      otp_app: :jido_compiler_test,
      actions: [],
      config_schema: Zoi.object(%{source: Zoi.string() |> Zoi.default("schema")})
  end

  defmodule HostReplacementPlugin do
    use Jido.Plugin,
      name: "host_replacement",
      state_key: :__host_default__,
      actions: [CompileAction],
      singleton: true
  end

  defmodule WrongReplacementPlugin do
    use Jido.Plugin,
      name: "wrong_replacement",
      state_key: :wrong_key,
      actions: [CompileAction],
      singleton: true
  end

  defmodule HostJido do
    def __default_plugins__, do: [HostDefaultPlugin]
  end

  defmodule ValidExtension do
    @behaviour Jido.Agent.Extension

    @impl true
    def validate_executable(%{enabled: enabled}) when is_boolean(enabled), do: :ok

    def validate_executable(_data) do
      {:error, Jido.Error.validation_error("extension data is invalid")}
    end

    @impl true
    def compile(data, metadata), do: {:ok, %{data: data, metadata: metadata}}
  end

  defmodule InvalidPlugin do
  end

  defmodule CompatAgent do
    use Jido.Agent,
      name: "compiler_compat_agent",
      default_plugins: false,
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
  end

  setup do
    Process.delete(:compiler_action_ran)
    Process.delete(:compiler_plugin_mounted)

    Application.put_env(
      :jido_compiler_test,
      EnvironmentSentinelPlugin,
      source: "application_env"
    )

    on_exit(fn ->
      Application.delete_env(:jido_compiler_test, EnvironmentSentinelPlugin)
    end)

    :ok
  end

  test "executable validation checks contracts without running Actions or mounting plugins" do
    definition =
      Agent.new!(
        name: "executable_agent",
        plugin_defaults: :none,
        plugins: [
          Plugin.new!(module: CompilePlugin),
          Plugin.new!(module: CallbackSentinelPlugin),
          Plugin.new!(module: EnvironmentSentinelPlugin)
        ]
      )

    assert {:ok, ^definition} = Agent.validate_executable(definition)
    assert {:ok, %Compiled{} = compiled} = Agent.compile(definition)

    assert Enum.find(compiled.plugin_instances, &(&1.module == EnvironmentSentinelPlugin)).config ==
             %{source: "schema"}

    refute Process.get(:compiler_action_ran)
    refute Process.get(:compiler_plugin_mounted)
    refute_receive {:compiler_callback_sentinel, _pid}, 20
    refute_receive :compiler_process_sentinel, 20

    invalid =
      Agent.new!(
        name: "invalid_executable_agent",
        plugin_defaults: :none,
        plugins: [Plugin.new!(module: InvalidPlugin)]
      )

    assert {:error, error} = Agent.validate_executable(invalid)
    assert Exception.message(error) =~ "plugin"
  end

  test "compile creates a derived plan and does not run Actions or mount plugins" do
    definition =
      Agent.new!(
        name: "compiled_agent",
        state_schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
        plugin_defaults: :none,
        plugins: [Plugin.new!(module: CompilePlugin)],
        extensions: [
          %{module: ValidExtension, data: %{enabled: true}, metadata: %{owner: "compiler"}}
        ]
      )

    assert {:ok, %Compiled{} = compiled} = Agent.compile(definition)
    assert compiled.agent == definition

    assert [%Jido.Plugin.Instance{module: CompilePlugin, config: %{limit: 5}}] =
             compiled.plugin_instances

    assert [%Jido.Plugin.Spec{module: CompilePlugin}] = compiled.plugin_specs
    assert Map.has_key?(compiled.action_index, CompileAction)
    assert compiled.capability_index.compile_test == [:compile_plugin]
    assert Enum.all?(compiled.routes, &match?(%Route{}, &1))
    assert Enum.any?(compiled.schedules, &match?({:plugin_schedule, _, _}, &1.job_id))

    assert compiled.extension_plans[ValidExtension] == %{
             data: %{enabled: true},
             metadata: %{owner: "compiler"}
           }

    assert compiled.semantic_identity == elem(Agent.semantic_identity(definition), 1)
    refute Map.has_key?(Map.from_struct(compiled), :strategy)
    refute Process.get(:compiler_action_ran)
    refute Process.get(:compiler_plugin_mounted)
  end

  test "host defaults and host config do not change the definition identity" do
    definition = Agent.new!(name: "host_bound_agent")
    original_map = Agent.to_map(definition)
    {:ok, identity} = Agent.semantic_identity(definition)

    assert {:ok, first} =
             Agent.compile(definition,
               jido: HostJido,
               plugin_configs: %{__host_default__: %{value: 10}}
             )

    assert {:ok, second} = Agent.compile(definition, default_plugins: [])

    assert hd(first.plugin_instances).config.value == 10
    assert second.plugin_instances == []
    assert first.semantic_identity == identity
    assert second.semantic_identity == identity
    assert Agent.to_map(definition) == original_map
  end

  test "default overrides validate selected keys and replacement state keys" do
    disabled =
      Agent.new!(
        name: "disabled_default_agent",
        plugin_defaults:
          PluginDefaults.new!(mode: :inherit, overrides: %{__host_default__: :disabled})
      )

    assert {:ok, %Compiled{plugin_instances: []}} =
             Agent.compile(disabled, default_plugins: [HostDefaultPlugin])

    replaced =
      Agent.new!(
        name: "replaced_default_agent",
        plugin_defaults:
          PluginDefaults.new!(
            mode: :inherit,
            overrides: %{
              __host_default__: Plugin.new!(module: HostReplacementPlugin)
            }
          )
      )

    assert {:ok, %Compiled{plugin_instances: [instance]}} =
             Agent.compile(replaced, default_plugins: [HostDefaultPlugin])

    assert instance.module == HostReplacementPlugin
    assert instance.state_key == :__host_default__

    wrong_key =
      Agent.new!(
        name: "wrong_replacement_agent",
        plugin_defaults:
          PluginDefaults.new!(
            overrides: %{
              __host_default__: Plugin.new!(module: WrongReplacementPlugin)
            }
          )
      )

    assert {:error, replacement_error} =
             Agent.compile(wrong_key, default_plugins: [HostDefaultPlugin])

    assert Exception.message(replacement_error) =~ "state key"

    unknown =
      Agent.new!(
        name: "unknown_override_agent",
        plugin_defaults: PluginDefaults.new!(overrides: %{unknown: :disabled})
      )

    assert {:error, unknown_error} =
             Agent.compile(unknown, default_plugins: [HostDefaultPlugin])

    assert Exception.message(unknown_error) =~ "override"
  end

  test "schedules validate cron, timezone, and merged route coverage" do
    schedule =
      Schedule.new!(
        name: "heartbeat",
        cron_expression: "*/5 * * * *",
        signal_type: "agent.heartbeat"
      )

    covered =
      Agent.new!(
        name: "covered_schedule_agent",
        plugin_defaults: :none,
        routes: [{"agent.*", CompileAction}],
        schedules: [schedule]
      )

    assert {:ok, compiled} = Agent.compile(covered)
    assert [compiled_schedule] = compiled.schedules
    assert compiled_schedule.job_id == {:agent_schedule, "covered_schedule_agent", "heartbeat"}

    uncovered = %{covered | routes: []}
    assert {:error, executable_coverage_error} = Agent.validate_executable(uncovered)
    assert Exception.message(executable_coverage_error) =~ "route"

    assert {:error, coverage_error} = Agent.compile(uncovered)
    assert Exception.message(coverage_error) =~ "route"

    invalid_cron =
      %{covered | schedules: [%{schedule | cron_expression: "not a cron expression"}]}

    assert {:error, cron_error} = Agent.compile(invalid_cron)
    assert Exception.message(cron_error) =~ "cron"

    invalid_timezone = %{covered | schedules: [%{schedule | timezone: "Invalid/Nowhere"}]}
    assert {:error, timezone_error} = Agent.compile(invalid_timezone)
    assert Exception.message(timezone_error) =~ "timezone"
  end

  test "instantiate applies all defaults, validates state, and preserves definition identity" do
    definition =
      Agent.new!(
        name: "instance_agent",
        state_schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
        plugin_defaults: :none,
        plugins: [Plugin.new!(module: CompilePlugin)]
      )

    assert {:ok, instance} =
             Agent.instantiate(definition,
               id: "instance-1",
               state: %{count: 2},
               agent_module: __MODULE__
             )

    assert instance.id == "instance-1"
    assert instance.agent_module == __MODULE__
    assert instance.state.count == 2
    assert instance.state.compile_plugin.enabled
    assert Agent.definition(instance) == definition
    assert Agent.semantic_identity(instance) == Agent.semantic_identity(definition)

    assert {:error, state_error} =
             Agent.instantiate(definition, state: %{count: "invalid"})

    assert Exception.message(state_error) =~ "state"
  end

  test "generated new delegates through the explicit instance boundary" do
    agent = CompatAgent.new(id: "compat-1", state: %{count: 3})

    assert %Agent{id: "compat-1", agent_module: CompatAgent} = agent
    assert agent.state.count == 3
    assert {:ok, ^agent} = CompatAgent.validate(agent)
  end
end
