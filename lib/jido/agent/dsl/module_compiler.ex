defmodule Jido.Agent.DSL.ModuleCompiler do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Agent.DSL.Lowerer
  alias Jido.Agent.Plugin
  alias Jido.Agent.PluginDefaults

  @compatibility_keys [
    :actions,
    :name,
    :description,
    :schema,
    :plugins,
    :default_plugins,
    :signal_routes,
    :schedules,
    :strategy,
    :jido,
    :category,
    :tags,
    :vsn
  ]
  @canonical_keys [
    :name,
    :description,
    :state_schema,
    :plugins,
    :plugin_defaults,
    :routes,
    :schedules,
    :metadata,
    :agent_extensions
  ]
  @spark_keys [:extensions, :fragments, :otp_app]

  @doc false
  defmacro __using__(opts_ast) do
    unless is_list(opts_ast) and Keyword.keyword?(opts_ast) do
      raise CompileError,
        file: __CALLER__.file,
        line: __CALLER__.line,
        description: "Agent options must be a keyword list"
    end

    spark_opts = Keyword.take(opts_ast, @spark_keys)
    agent_opts = Keyword.drop(opts_ast, @spark_keys)
    module_compiler = __MODULE__

    aliases =
      quote do
        alias Jido.Agent
        alias Jido.Agent.Command
        alias Jido.Agent.State, as: AgentState
        alias Jido.Agent.Strategy, as: AgentStrategy
        alias Jido.Plugin.Requirements, as: PluginRequirements
      end

    quote location: :keep do
      unquote(aliases)
      @behaviour Jido.Agent
      use Jido.Agent.DSL, unquote(spark_opts)
      @before_compile Jido.Agent.DSL.ModuleCompiler

      {root_opts, runtime_opts} =
        unquote(module_compiler).prepare_config!(unquote(agent_opts), __ENV__)

      @__jido_agent_root_opts__ root_opts
      @__jido_agent_runtime_opts__ runtime_opts

      @impl true
      def on_before_cmd(agent, action), do: {:ok, agent, action}

      @impl true
      def on_after_cmd(agent, _action, directives), do: {:ok, agent, directives}

      @impl true
      def signal_routes, do: __jido_authored_signal_routes__()

      @impl true
      def signal_routes(_ctx), do: signal_routes()

      @impl true
      def checkpoint(agent, ctx) do
        Jido.Agent.DSL.ModuleCompiler.checkpoint(__MODULE__, agent, ctx)
      end

      @impl true
      def restore(data, ctx) do
        Jido.Agent.DSL.ModuleCompiler.restore(__MODULE__, data, ctx)
      end

      defoverridable on_before_cmd: 2,
                     on_after_cmd: 3,
                     checkpoint: 2,
                     restore: 2,
                     signal_routes: 0,
                     signal_routes: 1

      defp __strategy_ctx__(jido_instance \\ nil, partition \\ nil) do
        %{
          agent_module: __MODULE__,
          strategy_opts: strategy_opts(),
          jido_instance: jido_instance,
          partition: partition
        }
      end

      defp __do_after_cmd__(agent, message, directives) do
        {:ok, agent, directives} = on_after_cmd(agent, message, directives)
        {agent, directives}
      end
    end
  end

  @doc false
  @spec prepare_config!(keyword(), Macro.Env.t()) :: {map(), map()} | no_return()
  def prepare_config!(raw_opts, env) do
    validate_keyword!(raw_opts, env)
    validate_known_keys!(raw_opts, env)
    validate_alias_conflicts!(raw_opts, env)

    opts = raw_opts |> Agent.expand_and_eval_literal_option(env) |> Map.new()

    state_schema =
      cond do
        Map.has_key?(opts, :state_schema) -> opts.state_schema
        Map.has_key?(opts, :schema) -> opts.schema
        true -> nil
      end

    if not is_nil(state_schema) do
      Jido.Action.ensure_static_schema!(state_schema, :state_schema, env)
    end

    strategy = compatibility_strategy!(opts, env)
    metadata = compatibility_metadata(Map.get(opts, :metadata, %{}), opts, env)

    root_opts =
      %{}
      |> copy_if_present(opts, :name)
      |> copy_if_present(opts, :description)
      |> put_if_present(opts, [:schema, :state_schema], :state_schema, state_schema)
      |> copy_if_present(opts, :plugins)
      |> put_if_present(
        opts,
        [:default_plugins, :plugin_defaults],
        :plugin_defaults,
        compatibility_plugin_defaults!(opts, env)
      )
      |> put_if_present(
        opts,
        [:signal_routes, :routes],
        :routes,
        Map.get(opts, :signal_routes, Map.get(opts, :routes))
      )
      |> copy_if_present(opts, :schedules)
      |> copy_if_present(opts, :agent_extensions)
      |> maybe_put(:metadata, metadata, metadata != %{} or Map.has_key?(opts, :metadata))

    runtime_opts = %{
      category: Map.get(opts, :category),
      compatibility_schedules: Map.get(opts, :schedules, []),
      compatibility_signal_routes: Map.get(opts, :signal_routes, Map.get(opts, :routes, [])),
      jido: Map.get(opts, :jido),
      strategy: strategy,
      tags: Map.get(opts, :tags, []),
      vsn: Map.get(opts, :vsn)
    }

    {root_opts, runtime_opts}
  rescue
    error in [CompileError] ->
      reraise error, __STACKTRACE__

    error ->
      raise CompileError,
        file: env.file,
        line: env.line,
        description: "Invalid Agent configuration: #{Exception.message(error)}"
  end

  @doc false
  defmacro __before_compile__(env), do: before_compile(env)

  @doc false
  @spec before_compile(Macro.Env.t()) :: Macro.t()
  def before_compile(env) do
    root_opts = Module.get_attribute(env.module, :__jido_agent_root_opts__)
    runtime_opts = Module.get_attribute(env.module, :__jido_agent_runtime_opts__)
    source_map = Lowerer.source_map(env.module, env.file)
    agent = lower_agent!(env, root_opts, source_map)

    Jido.Action.ensure_static_schema!(agent.state_schema, :state_schema, env)
    ensure_escapable!(agent, env)

    compile_opts = compile_opts(runtime_opts, source_map)

    compiled =
      agent
      |> agent_for_before_compile(env.module)
      |> compile_agent!(compile_opts, env, source_map)

    put_runtime_attributes(env.module, agent, compiled, runtime_opts)

    basic_accessors = Agent.__quoted_basic_accessors__()
    plugin_accessors = Agent.__quoted_plugin_accessors__()
    plugin_config_accessors = Agent.__quoted_plugin_config_accessors__()
    strategy_accessors = Agent.__quoted_strategy_accessors__()
    new_function = Agent.__quoted_new_function__()
    cmd_function = Agent.__quoted_cmd_function__()
    utility_functions = Agent.__quoted_utility_functions__()
    escaped_agent = Macro.escape(agent)
    escaped_source_map = Macro.escape(source_map)
    escaped_compile_opts = Macro.escape(compile_opts)

    aliases =
      quote do
        alias Jido.Agent
        alias Jido.Agent.Command
        alias Jido.Agent.State, as: AgentState
        alias Jido.Agent.Strategy, as: AgentStrategy
        alias Jido.Plugin.Requirements, as: PluginRequirements
      end

    quote location: :keep do
      unquote(aliases)
      unquote(basic_accessors)
      unquote(plugin_accessors)
      unquote(plugin_config_accessors)
      unquote(strategy_accessors)
      unquote(new_function)
      unquote(cmd_function)
      unquote(utility_functions)

      @doc false
      def __jido_authored_signal_routes__, do: @expanded_signal_routes

      @doc "Returns the inert canonical Agent definition."
      @spec agent() :: Jido.Agent.t()
      def agent, do: unquote(escaped_agent)

      @doc false
      @spec __jido_agent_source_map__() :: Jido.Agent.Compiled.source_map()
      def __jido_agent_source_map__, do: unquote(escaped_source_map)

      @doc "Returns derived compiled data for this Agent module."
      @spec compiled() :: Jido.Agent.Compiled.t()
      def compiled do
        compile_opts =
          Keyword.put(
            unquote(escaped_compile_opts),
            :compatibility_routes,
            signal_routes(%{agent_module: __MODULE__})
          )

        Jido.Agent.compile!(agent(), compile_opts)
      end
    end
  end

  @doc false
  def checkpoint(module, agent, ctx) do
    {state, externalized, externalized_keys} =
      Enum.reduce(module.plugin_instances(), {agent.state, %{}, %{}}, fn instance,
                                                                         {state_acc, ext_acc,
                                                                          keys_acc} ->
        plugin_state = Map.get(state_acc, instance.state_key)
        config = instance.config || %{}

        case instance.module.on_checkpoint(plugin_state, Map.put(ctx, :config, config)) do
          {:externalize, key, pointer} ->
            {Map.delete(state_acc, instance.state_key), Map.put(ext_acc, key, pointer),
             Map.put(keys_acc, key, instance.state_key)}

          :drop ->
            {Map.delete(state_acc, instance.state_key), ext_acc, keys_acc}

          :keep ->
            {state_acc, ext_acc, keys_acc}
        end
      end)

    base = %{
      version: 1,
      agent_module: module,
      id: agent.id,
      state: state
    }

    base =
      if externalized_keys == %{},
        do: base,
        else: Map.put(base, :externalized_keys, externalized_keys)

    {:ok, Map.merge(base, externalized)}
  end

  @doc false
  def restore(module, data, ctx) do
    data = normalize_keys(data)
    agent = module.new(id: data[:id])
    base_state = data[:state] || %{}
    agent = %{agent | state: Map.merge(agent.state, base_state)}
    externalized_keys = data[:externalized_keys] || %{}

    Enum.reduce_while(module.plugin_instances(), {:ok, agent}, fn instance, {:ok, acc} ->
      config = instance.config || %{}
      restore_ctx = Map.put(ctx, :config, config)

      external_key =
        Enum.find_value(externalized_keys, fn {key, state_key} ->
          if state_key == instance.state_key, do: key
        end)

      pointer = if external_key, do: data[external_key]

      if pointer do
        case instance.module.on_restore(pointer, restore_ctx) do
          {:ok, nil} ->
            {:cont, {:ok, acc}}

          {:ok, restored_state} ->
            {:cont, {:ok, %{acc | state: Map.put(acc.state, instance.state_key, restored_state)}}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      else
        {:cont, {:ok, acc}}
      end
    end)
  end

  defp normalize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {existing_atom_or_original(key), value}
      pair -> pair
    end)
  end

  defp existing_atom_or_original(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  defp agent_for_before_compile(agent, module) do
    has_dsl_schedule? =
      module
      |> Spark.Dsl.Extension.get_entities([:agent])
      |> Enum.any?(&match?(%Jido.Agent.DSL.Schedule{}, &1))

    if has_dsl_schedule?, do: agent, else: %{agent | schedules: []}
  end

  defp lower_agent!(env, root_opts, source_map) do
    case Lowerer.lower(env.module, root_opts, env) do
      {:ok, agent} -> agent
      {:error, error} -> raise_compile_error!(env, error, source_map)
    end
  end

  defp compile_agent!(agent, opts, env, source_map) do
    case Agent.compile(agent, opts) do
      {:ok, compiled} -> compiled
      {:error, error} -> raise_compile_error!(env, error, source_map)
    end
  end

  defp put_runtime_attributes(module, agent, compiled, runtime_opts) do
    compatibility_count = length(runtime_opts.compatibility_signal_routes)
    dsl_routes = Enum.drop(agent.routes, compatibility_count)
    compatibility_schedule_count = length(runtime_opts.compatibility_schedules)
    dsl_schedules = Enum.drop(agent.schedules, compatibility_schedule_count)

    validated_opts = %{
      name: agent.name,
      description: agent.description,
      schema: agent.state_schema,
      plugins: agent.plugins,
      signal_routes: runtime_opts.compatibility_signal_routes,
      schedules: runtime_opts.compatibility_schedules ++ dsl_schedules,
      strategy: runtime_opts.strategy,
      jido: runtime_opts.jido,
      category: runtime_opts.category,
      tags: runtime_opts.tags,
      vsn: runtime_opts.vsn
    }

    expanded_plugin_routes = Agent.Compiler.legacy_plugin_routes!(compiled.plugin_instances)

    expanded_plugin_schedules =
      Enum.flat_map(compiled.plugin_instances, &Jido.Plugin.Schedules.expand_schedules/1)

    schedule_routes =
      Enum.flat_map(compiled.plugin_instances, &Jido.Plugin.Schedules.schedule_routes/1)

    expanded_agent_schedules =
      Agent.Schedules.expand_schedules(
        runtime_opts.compatibility_schedules ++ dsl_schedules,
        agent.name
      )

    agent_schedule_routes = Agent.Schedules.schedule_routes(expanded_agent_schedules)

    validated_plugin_routes =
      case Jido.Plugin.Routes.detect_conflicts(
             expanded_plugin_routes ++ schedule_routes ++ agent_schedule_routes
           ) do
        {:ok, routes} -> routes
        {:error, conflicts} -> raise "Route conflicts detected: #{inspect(conflicts)}"
      end

    attributes = %{
      agent_definition: agent,
      expanded_signal_routes: runtime_opts.compatibility_signal_routes ++ dsl_routes,
      plugin_instances: compiled.plugin_instances,
      plugin_specs: compiled.plugin_specs,
      merged_schema: compatibility_merged_schema(agent, compiled),
      plugin_actions: compiled.plugin_specs |> Enum.flat_map(& &1.actions) |> Enum.uniq(),
      validated_plugin_routes: validated_plugin_routes,
      expanded_plugin_schedules: expanded_plugin_schedules,
      expanded_agent_schedules: expanded_agent_schedules,
      validated_opts: validated_opts
    }

    Enum.each(attributes, fn {name, value} -> Module.put_attribute(module, name, value) end)
  end

  defp compatibility_merged_schema(agent, compiled) do
    if agent.state_schema == [] and compiled.state_schema == [] and compiled.plugin_specs != [] do
      Zoi.object(%{})
    else
      compiled.state_schema
    end
  end

  defp compile_opts(runtime_opts, source_map) do
    [source_map: source_map]
    |> maybe_prepend(:jido, runtime_opts.jido)
  end

  defp maybe_prepend(opts, _key, nil), do: opts
  defp maybe_prepend(opts, key, value), do: [{key, value} | opts]

  defp ensure_escapable!(agent, env) do
    Macro.escape(agent)
    :ok
  rescue
    ArgumentError ->
      raise CompileError,
        file: env.file,
        line: env.line,
        description: "Agent definition must be static module data"
  end

  defp raise_compile_error!(env, error, source_map) do
    details = Map.get(error, :details, %{})
    location = source_location(details, source_map)
    description = compatibility_error_message(Exception.message(error))

    raise CompileError,
      file: Map.get(location, :file, env.file),
      line: Map.get(location, :line, env.line),
      description: description
  end

  defp compatibility_error_message("plugin state keys must be unique"),
    do: "Duplicate plugin state_keys"

  defp compatibility_error_message(message), do: message

  defp source_location(%{path: path}, source_map) when is_list(path) do
    candidates =
      path
      |> Enum.scan([], fn part, prefix -> prefix ++ [part] end)
      |> Enum.reverse()

    Enum.find_value(candidates, %{}, &Map.get(source_map, &1))
  end

  defp source_location(_details, _source_map), do: %{}

  defp validate_keyword!(opts, env) do
    unless Keyword.keyword?(opts) do
      compile_error!(env, "Agent options must be a keyword list")
    end

    case first_duplicate(Keyword.keys(opts)) do
      nil -> :ok
      key -> compile_error!(env, "Agent option is duplicated: #{inspect(key)}")
    end
  end

  defp validate_known_keys!(opts, env) do
    allowed = Enum.uniq(@compatibility_keys ++ @canonical_keys)

    case Enum.find(Keyword.keys(opts), &(&1 not in allowed)) do
      nil -> :ok
      key -> compile_error!(env, "unknown Agent option: #{inspect(key)}")
    end
  end

  defp validate_alias_conflicts!(opts, env) do
    for {left, right} <- [
          {:schema, :state_schema},
          {:signal_routes, :routes},
          {:default_plugins, :plugin_defaults}
        ],
        Keyword.has_key?(opts, left) and Keyword.has_key?(opts, right) do
      compile_error!(
        env,
        "Agent options #{inspect(left)} and #{inspect(right)} cannot be combined"
      )
    end
  end

  defp compatibility_strategy!(opts, env) do
    case Map.fetch(opts, :strategy) do
      :error ->
        Jido.Agent.Strategy.Direct

      {:ok, Jido.Agent.Strategy.Direct = strategy} ->
        warn_direct_strategy(env)
        strategy

      {:ok, {Jido.Agent.Strategy.Direct, options} = strategy} when is_list(options) ->
        warn_direct_strategy(env)
        strategy

      {:ok, _custom_strategy} ->
        compile_error!(
          env,
          "custom Agent strategies are not supported by v3 authoring; remove the strategy option and migrate execution to Actions, routes, or a trusted runtime module binding"
        )
    end
  end

  defp warn_direct_strategy(env) do
    IO.warn(
      "the Direct strategy option is obsolete and is not part of the canonical Agent definition; remove strategy: Jido.Agent.Strategy.Direct",
      Macro.Env.stacktrace(env)
    )
  end

  defp compatibility_metadata(metadata, _opts, _env)
       when is_map(metadata) and not is_struct(metadata) do
    metadata
  end

  defp compatibility_metadata(_metadata, _opts, env) do
    compile_error!(env, "Agent metadata must be a map")
  end

  defp compatibility_plugin_defaults!(opts, env) do
    cond do
      Map.has_key?(opts, :plugin_defaults) ->
        PluginDefaults.new!(opts.plugin_defaults)

      not Map.has_key?(opts, :default_plugins) ->
        nil

      is_nil(opts.default_plugins) ->
        PluginDefaults.new!(:inherit)

      opts.default_plugins == false ->
        PluginDefaults.new!(:none)

      match?(%PluginDefaults{}, opts.default_plugins) ->
        opts.default_plugins

      is_map(opts.default_plugins) ->
        overrides =
          Map.new(opts.default_plugins, fn
            {key, value} when value in [false, :disabled] -> {key, :disabled}
            {key, value} -> {key, compatibility_plugin!(value)}
          end)

        PluginDefaults.new!(mode: :inherit, overrides: overrides)

      true ->
        compile_error!(env, "default_plugins must be false or a map")
    end
  end

  defp compatibility_plugin!(%Plugin{} = plugin), do: plugin
  defp compatibility_plugin!(module) when is_atom(module), do: Plugin.new!(module: module)

  defp compatibility_plugin!({module, options}) when is_atom(module) and is_list(options) do
    {as, config} = Keyword.pop(options, :as)
    Plugin.new!(module: module, as: as, config: Map.new(config))
  end

  defp compatibility_plugin!({module, config}) when is_atom(module) and is_map(config),
    do: Plugin.new!(module: module, config: config)

  defp compatibility_plugin!(value), do: Plugin.new!(value)

  defp copy_if_present(acc, source, key) do
    if Map.has_key?(source, key), do: Map.put(acc, key, Map.fetch!(source, key)), else: acc
  end

  defp put_if_present(acc, source, source_keys, target_key, value) do
    if Enum.any?(source_keys, &Map.has_key?(source, &1)),
      do: Map.put(acc, target_key, value),
      else: acc
  end

  defp maybe_put(map, key, value, true), do: Map.put(map, key, value)
  defp maybe_put(map, _key, _value, false), do: map

  defp first_duplicate(values) do
    values
    |> Enum.reduce_while(MapSet.new(), fn value, seen ->
      if MapSet.member?(seen, value),
        do: {:halt, value},
        else: {:cont, MapSet.put(seen, value)}
    end)
    |> then(fn
      %MapSet{} -> nil
      duplicate -> duplicate
    end)
  end

  defp compile_error!(env, description) do
    raise CompileError, file: env.file, line: env.line, description: description
  end
end
