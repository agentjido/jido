defmodule Jido.Agent.Compiler do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Agent.Compiled
  alias Jido.Agent.Extension.Declaration, as: ExtensionDeclaration
  alias Jido.Agent.Plugin, as: AgentPlugin
  alias Jido.Agent.Schedule
  alias Jido.Agent.State, as: AgentState
  alias Jido.Error
  alias Jido.Plugin.Instance
  alias Jido.Plugin.Manifest
  alias Jido.Plugin.Spec
  alias Jido.Signal.Router
  alias Jido.Signal.Router.Route

  @compile_option_keys [
    :compatibility_routes,
    :default_plugins,
    :jido,
    :plugin_configs,
    :source_map
  ]
  @instantiate_option_keys [
    :__validate_state__,
    :agent_module,
    :compatibility_routes,
    :default_plugins,
    :id,
    :jido,
    :plugin_configs,
    :source_map,
    :state
  ]
  @plugin_route_priority -10
  @schedule_route_priority -20

  @doc false
  @spec validate_executable(Agent.t()) :: {:ok, Agent.t()} | {:error, Exception.t()}
  def validate_executable(%Agent{} = agent), do: validate_executable(agent, [])

  def validate_executable(value), do: Agent.Validation.invalid_subject(value)

  defp validate_executable(%Agent{} = agent, compatibility_routes) do
    safely(fn ->
      with {:ok, agent} <- Agent.validate(agent),
           {:ok, declarations} <- explicit_plugin_declarations(agent),
           {:ok, plugin_instances, _plugin_specs} <- materialize_plugins(declarations, %{}),
           :ok <- validate_plugin_set(plugin_instances, agent.state_schema),
           {:ok, plugin_routes} <- plugin_routes(plugin_instances),
           {:ok, plugin_schedules, schedule_routes} <- plugin_schedules(plugin_instances),
           {:ok, routes} <-
             normalize_routes(
               agent.routes ++ compatibility_routes,
               plugin_routes,
               schedule_routes
             ),
           :ok <- validate_route_actions(routes),
           {:ok, agent_schedules} <- agent_schedules(agent),
           :ok <- validate_schedules(plugin_schedules ++ agent_schedules),
           :ok <- validate_schedule_coverage(agent_schedules, routes),
           :ok <- validate_extensions(agent.extensions) do
        {:ok, agent}
      end
    end)
  end

  @doc false
  @spec materialize_plugin_declaration!(AgentPlugin.t()) :: Instance.t()
  def materialize_plugin_declaration!(%AgentPlugin{} = declaration) do
    case safely(fn -> materialize_plugin(declaration, %{}) end) do
      {:ok, instance, _spec} ->
        instance

      {:error, validation_error} ->
        raise CompileError, description: Exception.message(validation_error)
    end
  end

  @doc false
  @spec plugin_spec(Instance.t()) :: Spec.t()
  def plugin_spec(%Instance{} = instance), do: spec_from_instance(instance)

  @doc false
  @spec legacy_plugin_routes!([Instance.t()]) :: [{String.t(), module(), keyword()}]
  def legacy_plugin_routes!(instances) when is_list(instances) do
    case safely(fn -> plugin_routes(instances) end) do
      {:ok, routes} ->
        Enum.map(routes, fn {path, target, priority} ->
          {path, target, [priority: priority]}
        end)

      {:error, validation_error} ->
        raise CompileError, description: Exception.message(validation_error)
    end
  end

  @doc false
  @spec compile(Agent.t(), keyword() | map()) ::
          {:ok, Compiled.t()} | {:error, Exception.t()}
  def compile(agent, opts \\ [])

  def compile(%Agent{} = agent, opts) do
    safely(fn ->
      with {:ok, opts} <- compile_options(opts),
           {:ok, agent} <- Agent.validate(agent),
           {:ok, declarations} <- effective_plugin_declarations(agent, opts),
           {:ok, plugin_instances, plugin_specs} <-
             materialize_plugins(declarations, opts.plugin_configs),
           :ok <- validate_plugin_set(plugin_instances, agent.state_schema),
           {:ok, state_schema} <- merge_state_schema(agent.state_schema, plugin_specs),
           {:ok, plugin_routes} <- plugin_routes(plugin_instances),
           {:ok, plugin_schedules, schedule_routes} <- plugin_schedules(plugin_instances),
           {:ok, routes} <-
             normalize_routes(
               agent.routes ++ opts.compatibility_routes,
               plugin_routes,
               schedule_routes
             ),
           :ok <- validate_route_actions(routes),
           {:ok, agent_schedules} <- agent_schedules(agent),
           schedules = plugin_schedules ++ agent_schedules,
           :ok <- validate_schedules(schedules),
           :ok <- validate_schedule_coverage(agent_schedules, routes),
           :ok <- validate_extensions(agent.extensions),
           {:ok, semantic_identity} <- Agent.semantic_identity(agent),
           {:ok, extension_plans} <- compile_extensions(agent.extensions) do
        {:ok,
         %Compiled{
           agent: Agent.definition(agent),
           state_schema: state_schema,
           plugin_instances: plugin_instances,
           plugin_specs: plugin_specs,
           action_index: action_index(plugin_specs, routes),
           capability_index: capability_index(plugin_instances),
           routes: routes,
           schedules: schedules,
           extension_plans: extension_plans,
           semantic_identity: semantic_identity,
           source_map: opts.source_map
         }}
      end
    end)
  end

  def compile(value, _opts), do: Agent.Validation.invalid_subject(value)

  @doc false
  @spec instantiate(Agent.t(), keyword() | map()) ::
          {:ok, Agent.t()} | {:error, Exception.t()}
  def instantiate(agent, opts \\ [])

  def instantiate(%Agent{} = agent, opts) do
    safely(fn ->
      with {:ok, opts} <- instantiate_options(opts),
           {:ok, compiled} <- compile(agent, Map.take(opts, @compile_option_keys)),
           {:ok, id} <- instance_id(opts.id),
           {:ok, agent_module} <- agent_module(opts.agent_module),
           {:ok, state} <- initial_state(compiled, opts.state),
           instance = %{
             compiled.agent
             | id: id,
               state: state,
               agent_module: agent_module
           },
           {:ok, instance} <- mount_plugins(instance, compiled.plugin_instances),
           {:ok, state} <-
             maybe_validate_instance_state(
               instance.state,
               compiled.state_schema,
               opts.__validate_state__
             ) do
        {:ok, %{instance | state: state}}
      end
    end)
  end

  def instantiate(value, _opts), do: Agent.Validation.invalid_subject(value)

  defp safely(fun) do
    fun.()
  rescue
    error -> {:error, normalize_error(error)}
  catch
    kind, reason ->
      {:error, error("Agent executable preparation failed", %{kind: kind, reason: reason})}
  end

  defp normalize_error(exception), do: exception

  defp compile_options(opts) do
    with {:ok, opts} <- options_map(opts, @compile_option_keys, "compile"),
         :ok <- jido_option(Map.get(opts, :jido)),
         {:ok, defaults} <- default_plugins_option(opts),
         {:ok, plugin_configs} <- plugin_configs(Map.get(opts, :plugin_configs, %{})),
         {:ok, compatibility_routes} <-
           compatibility_routes(Map.get(opts, :compatibility_routes, [])),
         {:ok, source_map} <- source_map(Map.get(opts, :source_map, %{})) do
      {:ok,
       %{
         jido: Map.get(opts, :jido),
         default_plugins: defaults,
         default_plugins?: Map.has_key?(opts, :default_plugins),
         plugin_configs: plugin_configs,
         compatibility_routes: compatibility_routes,
         source_map: source_map
       }}
    end
  end

  defp instantiate_options(opts) do
    with {:ok, opts} <- options_map(opts, @instantiate_option_keys, "instantiate"),
         :ok <- state_option(Map.get(opts, :state, %{})),
         :ok <- validate_state_option(Map.get(opts, :__validate_state__, true)) do
      {:ok,
       opts
       |> Map.put_new(:__validate_state__, true)
       |> Map.put_new(:agent_module, nil)
       |> Map.put_new(:id, nil)
       |> Map.put_new(:state, %{})}
    end
  end

  defp options_map(opts, allowed, label) when is_list(opts) do
    if Keyword.keyword?(opts) do
      duplicate = opts |> Keyword.keys() |> duplicate_value()

      if duplicate do
        {:error, error("Agent #{label} option is duplicated", %{option: duplicate})}
      else
        opts |> Map.new() |> options_map(allowed, label)
      end
    else
      {:error, error("Agent #{label} options must be a keyword list or map")}
    end
  end

  defp options_map(opts, allowed, label) when is_map(opts) and not is_struct(opts) do
    case Map.keys(opts) -- allowed do
      [] -> {:ok, opts}
      [option | _rest] -> {:error, error("unknown Agent #{label} option", %{option: option})}
    end
  end

  defp options_map(_opts, _allowed, label),
    do: {:error, error("Agent #{label} options must be a keyword list or map")}

  defp duplicate_value(values) do
    Enum.reduce_while(values, MapSet.new(), fn value, seen ->
      if MapSet.member?(seen, value),
        do: {:halt, value},
        else: {:cont, MapSet.put(seen, value)}
    end)
    |> then(fn
      %MapSet{} -> nil
      duplicate -> duplicate
    end)
  end

  defp jido_option(nil), do: :ok

  defp jido_option(jido) when is_atom(jido) and jido not in [true, false], do: :ok

  defp jido_option(_jido),
    do: {:error, error("Agent compile jido option must be a module atom")}

  defp default_plugins_option(opts) do
    if Map.has_key?(opts, :default_plugins) do
      case Map.get(opts, :default_plugins) do
        defaults when is_list(defaults) -> {:ok, defaults}
        nil -> {:ok, nil}
        _value -> {:error, error("Agent compile default_plugins option must be a list")}
      end
    else
      {:ok, nil}
    end
  end

  defp plugin_configs(configs) when is_map(configs) and not is_struct(configs) do
    Enum.reduce_while(configs, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      with :ok <- plugin_config_key(key),
           {:ok, config} <- config_map(value, "host plugin config") do
        {:cont, {:ok, Map.put(acc, key, config)}}
      else
        {:error, validation_error} -> {:halt, {:error, validation_error}}
      end
    end)
  end

  defp plugin_configs(_configs),
    do: {:error, error("Agent compile plugin_configs option must be a map")}

  defp compatibility_routes(routes) when is_list(routes) do
    case Router.normalize(routes) do
      {:ok, routes} ->
        {:ok, routes}

      {:error, reason} ->
        {:error, error("Agent compatibility routes are invalid", %{reason: reason})}
    end
  end

  defp compatibility_routes(_routes),
    do: {:error, error("Agent compatibility routes must be a list")}

  defp plugin_config_key(key) when is_atom(key) and key not in [nil, true, false], do: :ok

  defp plugin_config_key(_key),
    do: {:error, error("host plugin config keys must be module or state-key atoms")}

  defp source_map(source_map) when is_map(source_map) and not is_struct(source_map) do
    Enum.reduce_while(source_map, {:ok, %{}}, fn {path, location}, {:ok, acc} ->
      with :ok <- source_path(path),
           :ok <- source_location(location) do
        {:cont, {:ok, Map.put(acc, path, location)}}
      else
        {:error, validation_error} -> {:halt, {:error, validation_error}}
      end
    end)
  end

  defp source_map(_source_map), do: {:error, error("Agent source map must be a map")}

  defp source_path(path) when is_list(path) do
    if not List.improper?(path) and Enum.all?(path, &source_path_segment?/1),
      do: :ok,
      else: {:error, error("Agent source-map path is invalid", %{path: path})}
  end

  defp source_path(path),
    do: {:error, error("Agent source-map path must be a list", %{path: path})}

  defp source_path_segment?(value) when is_binary(value), do: String.valid?(value)
  defp source_path_segment?(value) when is_atom(value), do: not is_nil(value)
  defp source_path_segment?(value) when is_integer(value), do: value >= 0
  defp source_path_segment?(_value), do: false

  defp source_location(location) when is_map(location) and not is_struct(location) do
    unknown = Map.keys(location) -- [:column, :file, :line]

    cond do
      unknown != [] ->
        {:error, error("Agent source location contains an unknown field", %{field: hd(unknown)})}

      not valid_source_file?(Map.get(location, :file)) ->
        {:error, error("Agent source location file must be valid UTF-8 text")}

      not valid_source_position?(Map.get(location, :line)) ->
        {:error, error("Agent source location line must be a positive integer")}

      not valid_source_position?(Map.get(location, :column)) ->
        {:error, error("Agent source location column must be a positive integer")}

      true ->
        :ok
    end
  end

  defp source_location(_location),
    do: {:error, error("Agent source location must be a map")}

  defp valid_source_file?(nil), do: true
  defp valid_source_file?(file) when is_binary(file), do: String.valid?(file)
  defp valid_source_file?(_file), do: false
  defp valid_source_position?(nil), do: true
  defp valid_source_position?(value), do: is_integer(value) and value > 0

  defp explicit_plugin_declarations(agent) do
    replacements =
      agent.plugin_defaults.overrides
      |> Map.values()
      |> Enum.reject(&(&1 == :disabled))

    {:ok, agent.plugins ++ replacements}
  end

  defp effective_plugin_declarations(agent, opts) do
    with {:ok, host_defaults} <- selected_host_defaults(opts),
         {:ok, host_defaults} <- canonical_plugin_declarations(host_defaults, "host default"),
         {:ok, defaults} <- apply_default_policy(host_defaults, agent.plugin_defaults) do
      {:ok, defaults ++ agent.plugins}
    end
  end

  defp selected_host_defaults(%{default_plugins?: true, default_plugins: nil}),
    do: {:ok, Jido.Agent.DefaultPlugins.package_defaults()}

  defp selected_host_defaults(%{default_plugins?: true, default_plugins: defaults}),
    do: {:ok, defaults}

  defp selected_host_defaults(%{jido: jido}) when not is_nil(jido) do
    case Code.ensure_compiled(jido) do
      {:module, _module} ->
        if function_exported?(jido, :__default_plugins__, 0) do
          case jido.__default_plugins__() do
            defaults when is_list(defaults) ->
              {:ok, defaults}

            _value ->
              {:error, error("selected Jido default plugins must be a list", %{jido: jido})}
          end
        else
          {:error, error("selected Jido module does not provide default plugins", %{jido: jido})}
        end

      {:error, reason} ->
        {:error,
         error("selected Jido module could not be compiled", %{jido: jido, reason: reason})}
    end
  end

  defp selected_host_defaults(_opts),
    do: {:ok, Jido.Agent.DefaultPlugins.package_defaults()}

  defp canonical_plugin_declarations(declarations, label) do
    declarations
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {declaration, index}, {:ok, acc} ->
      case canonical_plugin_declaration(declaration) do
        {:ok, plugin} ->
          {:cont, {:ok, [plugin | acc]}}

        {:error, validation_error} ->
          {:halt,
           {:error,
            prefix_error(validation_error, [
              String.to_atom(String.replace(label, " ", "_")),
              index
            ])}}
      end
    end)
    |> reverse_ok()
  end

  defp canonical_plugin_declaration(%AgentPlugin{} = plugin), do: {:ok, plugin}

  defp canonical_plugin_declaration(module) when is_atom(module),
    do: AgentPlugin.new(module: module)

  defp canonical_plugin_declaration({module, opts}) when is_atom(module) and is_list(opts) do
    if Keyword.keyword?(opts) do
      {as, config} = Keyword.pop(opts, :as)
      AgentPlugin.new(module: module, as: as, config: Map.new(config))
    else
      {:error, error("plugin declaration options must be a keyword list")}
    end
  end

  defp canonical_plugin_declaration({module, config}) when is_atom(module) and is_map(config),
    do: AgentPlugin.new(module: module, config: config)

  defp canonical_plugin_declaration(_declaration),
    do: {:error, error("plugin declaration is invalid")}

  defp apply_default_policy(defaults, policy) do
    with {:ok, index} <- default_index(defaults),
         :ok <- validate_override_keys(policy.overrides, index),
         :ok <- validate_replacements(policy.overrides, index) do
      selected =
        if policy.mode == :none do
          []
        else
          Enum.flat_map(defaults, fn declaration ->
            {:ok, manifest} = plugin_manifest(declaration.module)
            state_key = Instance.derive_state_key(manifest.state_key, declaration.as)

            case Map.get(policy.overrides, state_key) do
              nil -> [declaration]
              :disabled -> []
              %AgentPlugin{} = replacement -> [replacement]
            end
          end)
        end

      {:ok, selected}
    end
  end

  defp default_index(defaults) do
    Enum.reduce_while(defaults, {:ok, %{}}, fn declaration, {:ok, acc} ->
      with {:ok, manifest} <- plugin_manifest(declaration.module) do
        state_key = Instance.derive_state_key(manifest.state_key, declaration.as)

        if Map.has_key?(acc, state_key) do
          {:halt,
           {:error,
            error("selected host defaults have a duplicate state key", %{state_key: state_key})}}
        else
          {:cont, {:ok, Map.put(acc, state_key, declaration)}}
        end
      else
        {:error, validation_error} -> {:halt, {:error, validation_error}}
      end
    end)
  end

  defp validate_override_keys(overrides, index) do
    case Map.keys(overrides) -- Map.keys(index) do
      [] ->
        :ok

      keys ->
        {:error,
         error("plugin-default override keys are not in the selected host defaults", %{keys: keys})}
    end
  end

  defp validate_replacements(overrides, index) do
    Enum.reduce_while(overrides, :ok, fn
      {_key, :disabled}, :ok ->
        {:cont, :ok}

      {key, %AgentPlugin{} = replacement}, :ok ->
        with {:ok, manifest} <- plugin_manifest(replacement.module) do
          replacement_key = Instance.derive_state_key(manifest.state_key, replacement.as)

          if replacement_key == key do
            {:cont, :ok}
          else
            {:halt,
             {:error,
              error("replacement default plugin must preserve the selected state key", %{
                expected: key,
                actual: replacement_key,
                selected: index[key].module,
                replacement: replacement.module
              })}}
          end
        else
          {:error, validation_error} -> {:halt, {:error, validation_error}}
        end
    end)
  end

  defp materialize_plugins(declarations, host_configs) do
    declarations
    |> Enum.reduce_while({:ok, [], []}, fn declaration, {:ok, instances, specs} ->
      case materialize_plugin(declaration, host_configs) do
        {:ok, instance, spec} ->
          {:cont, {:ok, [instance | instances], [spec | specs]}}

        {:error, validation_error} ->
          {:halt, {:error, validation_error}}
      end
    end)
    |> case do
      {:ok, instances, specs} -> {:ok, Enum.reverse(instances), Enum.reverse(specs)}
      {:error, _error} = result -> result
    end
  end

  defp materialize_plugin(%AgentPlugin{} = declaration, host_configs) do
    with {:ok, manifest} <- plugin_manifest(declaration.module),
         :ok <- singleton_alias(manifest, declaration.as),
         state_key = Instance.derive_state_key(manifest.state_key, declaration.as),
         route_prefix = Instance.derive_route_prefix(manifest.name, declaration.as),
         {:ok, config} <- resolved_plugin_config(declaration, state_key, manifest, host_configs) do
      instance = %Instance{
        module: declaration.module,
        as: declaration.as,
        config: config,
        manifest: manifest,
        state_key: state_key,
        route_prefix: route_prefix
      }

      spec = spec_from_instance(instance)

      {:ok, instance, spec}
    end
  end

  defp spec_from_instance(%Instance{} = instance) do
    manifest = instance.manifest

    %Spec{
      module: instance.module,
      name: manifest.name,
      state_key: instance.state_key,
      description: manifest.description,
      category: manifest.category,
      vsn: manifest.vsn,
      schema: manifest.schema,
      config_schema: manifest.config_schema,
      config: instance.config,
      signal_patterns: manifest.signal_patterns || [],
      tags: manifest.tags || [],
      actions: manifest.actions || []
    }
  end

  defp plugin_manifest(module) do
    with :ok <- ensure_module(module, "plugin"),
         :ok <- ensure_behaviour(module, Jido.Plugin, "plugin"),
         true <- function_exported?(module, :__jido_compiler_manifest__, 0) do
      case module.__jido_compiler_manifest__() do
        %Manifest{module: ^module} = manifest ->
          with :ok <- validate_plugin_manifest(manifest), do: {:ok, manifest}

        value ->
          {:error, error("plugin compiler manifest is invalid", %{plugin: module, value: value})}
      end
    else
      false ->
        {:error, error("plugin does not expose inert compiler metadata", %{plugin: module})}

      {:error, _error} = result ->
        result
    end
  end

  defp validate_plugin_manifest(manifest) do
    with :ok <- static_state_schema(manifest.schema, manifest.module),
         :ok <- static_config_schema(manifest.config_schema, manifest.module),
         :ok <- validate_manifest_actions(manifest.actions, manifest.module),
         :ok <- validate_capabilities(manifest.capabilities, manifest.module) do
      :ok
    end
  end

  defp static_state_schema(nil, _module), do: :ok

  defp static_state_schema(schema, module) do
    with :ok <- static_schema_data(schema, "plugin state", module),
         :ok <- schema_shape(schema, module) do
      :ok
    end
  end

  defp static_config_schema(nil, _module), do: :ok

  defp static_config_schema(schema, module) do
    with :ok <- static_schema_data(schema, "plugin config", module) do
      case Jido.Action.validate_config_schema(schema) do
        :ok ->
          :ok

        {:error, reason} ->
          {:error, error("plugin config schema is invalid", %{plugin: module, reason: reason})}
      end
    end
  end

  defp static_schema_data(schema, label, module) do
    case Jido.Action.validate_static_data(schema) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, error("#{label} schema must be static", %{module: module, reason: reason})}
    end
  end

  defp schema_shape(schema, module) do
    case AgentState.validate_schema(schema) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, error("plugin state schema is invalid", %{plugin: module, reason: reason})}
    end
  end

  defp validate_manifest_actions(actions, plugin) when is_list(actions) do
    Enum.reduce_while(actions, :ok, fn action, :ok ->
      case validate_action(action) do
        :ok ->
          {:cont, :ok}

        {:error, validation_error} ->
          {:halt, {:error, prefix_error(validation_error, [:plugins, plugin, :actions])}}
      end
    end)
  end

  defp validate_manifest_actions(_actions, plugin),
    do: {:error, error("plugin actions must be a list", %{plugin: plugin})}

  defp validate_capabilities(capabilities, _plugin) when is_list(capabilities) do
    if Enum.all?(capabilities, &valid_capability?/1),
      do: :ok,
      else: {:error, error("plugin capabilities must be atoms")}
  end

  defp validate_capabilities(_capabilities, plugin),
    do: {:error, error("plugin capabilities must be a list", %{plugin: plugin})}

  defp valid_capability?(value), do: is_atom(value) and value not in [nil, true, false]

  defp singleton_alias(%Manifest{singleton: true}, as) when not is_nil(as),
    do: {:error, error("singleton plugin cannot use an alias", %{alias: as})}

  defp singleton_alias(_manifest, _as), do: :ok

  defp resolved_plugin_config(declaration, state_key, manifest, host_configs) do
    host_module_config = Map.get(host_configs, declaration.module, %{})
    host_state_config = Map.get(host_configs, state_key, %{})

    merged =
      host_module_config
      |> Map.merge(host_state_config)
      |> Map.merge(declaration.config)

    case manifest.config_schema do
      nil ->
        {:ok, merged}

      schema ->
        case Zoi.parse(schema, merged) do
          {:ok, config} when is_map(config) ->
            {:ok, config}

          {:ok, config} ->
            {:error,
             error("plugin config schema must return a map", %{
               plugin: declaration.module,
               value: config
             })}

          {:error, reason} ->
            {:error,
             error("plugin config is invalid", %{plugin: declaration.module, reason: reason})}
        end
    end
  end

  defp validate_plugin_set(instances, base_schema) do
    with :ok <- unique_state_keys(instances),
         :ok <- singleton_instances(instances),
         :ok <- state_key_collisions(instances, base_schema),
         :ok <- plugin_requirements(instances) do
      :ok
    end
  end

  defp unique_state_keys(instances) do
    case instances |> Enum.map(& &1.state_key) |> duplicate_value() do
      nil -> :ok
      key -> {:error, error("plugin state keys must be unique", %{state_key: key})}
    end
  end

  defp singleton_instances(instances) do
    duplicate =
      instances
      |> Enum.filter(& &1.manifest.singleton)
      |> Enum.map(& &1.module)
      |> duplicate_value()

    if duplicate,
      do: {:error, error("singleton plugin is declared more than once", %{plugin: duplicate})},
      else: :ok
  end

  defp state_key_collisions(instances, %Zoi.Types.Map{fields: fields}) do
    keys = Keyword.keys(fields)

    case Enum.find(instances, &(&1.state_key in keys)) do
      nil ->
        :ok

      instance ->
        {:error,
         error("plugin state key collides with Agent state schema", %{
           state_key: instance.state_key
         })}
    end
  end

  defp state_key_collisions(_instances, []), do: :ok

  defp plugin_requirements(instances) do
    names = MapSet.new(instances, & &1.manifest.name)

    Enum.reduce_while(instances, :ok, fn instance, :ok ->
      missing =
        Enum.reject(instance.manifest.requires || [], fn
          {:config, key} when is_atom(key) -> not is_nil(Map.get(instance.config, key))
          {:plugin, name} -> MapSet.member?(names, to_string(name))
          {:app, app} when is_atom(app) -> not is_nil(Application.spec(app))
          _requirement -> true
        end)

      if missing == [] do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          error("plugin requirements are not satisfied", %{
            plugin: instance.module,
            requirements: missing
          })}}
      end
    end)
  end

  defp merge_state_schema(base_schema, specs) do
    plugin_fields =
      specs
      |> Enum.reject(&is_nil(&1.schema))
      |> Map.new(&{&1.state_key, &1.schema})

    plugin_schema = if plugin_fields == %{}, do: nil, else: Zoi.object(plugin_fields)

    merged =
      case {base_schema, plugin_schema} do
        {[], nil} -> []
        {[], plugin_schema} -> plugin_schema
        {base_schema, nil} -> base_schema
        {base_schema, plugin_schema} -> Zoi.extend(base_schema, plugin_schema)
      end

    {:ok, merged}
  end

  defp plugin_routes(instances) do
    instances
    |> Enum.reduce_while({:ok, []}, fn instance, {:ok, acc} ->
      case expand_plugin_routes(instance) do
        {:ok, routes} -> {:cont, {:ok, acc ++ routes}}
        {:error, validation_error} -> {:halt, {:error, validation_error}}
      end
    end)
  end

  defp expand_plugin_routes(instance) do
    routes = instance.manifest.signal_routes || []

    routes =
      cond do
        routes != [] ->
          routes

        function_exported?(instance.module, :__jido_compiler_dynamic_routes__?, 0) and
            instance.module.__jido_compiler_dynamic_routes__?() ->
          []

        true ->
          for pattern <- instance.manifest.signal_patterns || [],
              action <- instance.manifest.actions || [] do
            {pattern, action}
          end
      end

    Enum.reduce_while(routes, {:ok, []}, fn route, {:ok, acc} ->
      case expand_plugin_route(route, instance.route_prefix) do
        {:ok, expanded} -> {:cont, {:ok, [expanded | acc]}}
        {:error, validation_error} -> {:halt, {:error, validation_error}}
      end
    end)
    |> reverse_ok()
  end

  defp expand_plugin_route({path, target}, prefix) when is_binary(path),
    do: {:ok, {prefixed_path(prefix, path), target, @plugin_route_priority}}

  defp expand_plugin_route({path, target, priority}, prefix)
       when is_binary(path) and is_integer(priority),
       do: {:ok, {prefixed_path(prefix, path), target, priority}}

  defp expand_plugin_route({path, target, opts}, prefix)
       when is_binary(path) and is_list(opts) do
    if Keyword.keyword?(opts) do
      {:ok,
       {prefixed_path(prefix, path), target, Keyword.get(opts, :priority, @plugin_route_priority)}}
    else
      {:error, error("plugin route options must be a keyword list")}
    end
  end

  defp expand_plugin_route(_route, _prefix),
    do: {:error, error("plugin route is invalid")}

  defp plugin_schedules(instances) do
    instances
    |> Enum.reduce_while({:ok, [], []}, fn instance, {:ok, schedules, routes} ->
      case expand_plugin_schedules(instance) do
        {:ok, expanded} ->
          schedule_routes =
            Enum.map(expanded, &{&1.signal_type, &1.action, @schedule_route_priority})

          {:cont, {:ok, schedules ++ expanded, routes ++ schedule_routes}}

        {:error, validation_error} ->
          {:halt, {:error, validation_error}}
      end
    end)
  end

  defp expand_plugin_schedules(instance) do
    (instance.manifest.schedules || [])
    |> Enum.reduce_while({:ok, []}, fn schedule, {:ok, acc} ->
      case expand_plugin_schedule(schedule, instance) do
        {:ok, expanded} -> {:cont, {:ok, [expanded | acc]}}
        {:error, validation_error} -> {:halt, {:error, validation_error}}
      end
    end)
    |> reverse_ok()
  end

  defp expand_plugin_schedule({cron, action}, instance),
    do: expand_plugin_schedule({cron, action, []}, instance)

  defp expand_plugin_schedule({cron, action, opts}, instance)
       when is_binary(cron) and is_atom(action) and is_list(opts) do
    if Keyword.keyword?(opts) do
      timezone = Keyword.get(opts, :tz, "Etc/UTC")

      signal_type =
        case Keyword.get(opts, :signal) do
          nil -> "#{instance.route_prefix}.__schedule__.#{action_name(action)}"
          signal when is_binary(signal) -> prefixed_path(instance.route_prefix, signal)
          _value -> nil
        end

      if is_binary(signal_type) do
        {:ok,
         %{
           cron_expression: cron,
           action: action,
           job_id: {:plugin_schedule, instance.state_key, action},
           signal_type: signal_type,
           timezone: timezone
         }}
      else
        {:error, error("plugin schedule signal must be text", %{plugin: instance.module})}
      end
    else
      {:error,
       error("plugin schedule options must be a keyword list", %{plugin: instance.module})}
    end
  end

  defp expand_plugin_schedule(_schedule, instance),
    do: {:error, error("plugin schedule is invalid", %{plugin: instance.module})}

  defp agent_schedules(agent) do
    schedules =
      Enum.map(agent.schedules, fn %Schedule{} = schedule ->
        %{
          cron_expression: schedule.cron_expression,
          action: nil,
          job_id: {:agent_schedule, agent.name, schedule.name},
          signal_type: schedule.signal_type,
          timezone: schedule.timezone,
          data: schedule.data
        }
      end)

    {:ok, schedules}
  end

  defp normalize_routes(agent_routes, plugin_routes, schedule_routes) do
    Router.normalize(agent_routes ++ plugin_routes ++ schedule_routes)
    |> case do
      {:ok, routes} -> {:ok, routes}
      {:error, reason} -> {:error, error("Agent routes are invalid", %{reason: reason})}
    end
  end

  defp validate_route_actions(routes) do
    Enum.reduce_while(routes, :ok, fn %Route{target: target}, :ok ->
      case route_action(target) do
        {:ok, action} ->
          case validate_action(action) do
            :ok -> {:cont, :ok}
            {:error, validation_error} -> {:halt, {:error, validation_error}}
          end

        {:error, validation_error} ->
          {:halt, {:error, validation_error}}
      end
    end)
  end

  defp route_action({action, params}) when is_atom(action) and is_map(params), do: {:ok, action}
  defp route_action(action) when is_atom(action), do: {:ok, action}

  defp route_action(target),
    do: {:error, error("Agent route target must be an executable module", %{target: target})}

  defp validate_action(action) do
    with :ok <- ensure_module(action, "Action"),
         :ok <- ensure_behaviour(action, Jido.Action, "Action"),
         :ok <- ensure_exports(action, [name: 0, schema: 0, output_schema: 0, run: 2], "Action"),
         schema <- action.schema(),
         output_schema <- action.output_schema(),
         :ok <- static_schema_data(schema, "Action input", action),
         :ok <- static_schema_data(output_schema, "Action output", action),
         :ok <- action_schema_shape(schema, action, :input),
         :ok <- action_schema_shape(output_schema, action, :output) do
      :ok
    end
  end

  defp action_schema_shape(schema, action, field) do
    case Jido.Action.validate_action_schema(schema) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         error("Action schema is invalid", %{action: action, field: field, reason: reason})}
    end
  end

  defp validate_schedules(schedules) do
    Enum.reduce_while(schedules, :ok, fn schedule, :ok ->
      with :ok <- validate_cron(schedule.cron_expression, schedule.job_id),
           :ok <- validate_timezone(schedule.timezone, schedule.job_id) do
        {:cont, :ok}
      else
        {:error, validation_error} -> {:halt, {:error, validation_error}}
      end
    end)
  end

  defp validate_cron(expression, job_id) when is_binary(expression) do
    extended = length(String.split(expression)) > 5

    case Crontab.CronExpression.Parser.parse(expression, extended) do
      {:ok, _expression} ->
        :ok

      {:error, reason} ->
        {:error,
         error("Agent schedule cron expression is invalid", %{job_id: job_id, reason: reason})}
    end
  end

  defp validate_cron(_expression, job_id),
    do: {:error, error("Agent schedule cron expression must be text", %{job_id: job_id})}

  defp validate_timezone(timezone, job_id) when is_binary(timezone) do
    if known_timezone?(timezone) do
      :ok
    else
      {:error, error("Agent schedule timezone is invalid", %{job_id: job_id, timezone: timezone})}
    end
  end

  defp validate_timezone(_timezone, job_id),
    do: {:error, error("Agent schedule timezone must be text", %{job_id: job_id})}

  defp known_timezone?(timezone) do
    valid_name =
      timezone != "" and
        not String.contains?(timezone, ["..", "\\", "\0"]) and
        Regex.match?(~r/^[A-Za-z0-9_+.-]+(?:\/[A-Za-z0-9_+.-]+)*$/, timezone)

    valid_name and
      (timezone in ["Etc/UTC", "UTC"] or
         system_time_zone_exists?(timezone))
  end

  defp system_time_zone_exists?(timezone) do
    Enum.any?(["/usr/share/zoneinfo", "/var/db/timezone/zoneinfo"], fn root ->
      root |> Path.join(timezone) |> File.regular?()
    end)
  end

  defp validate_schedule_coverage(schedules, routes) do
    Enum.reduce_while(schedules, :ok, fn schedule, :ok ->
      if Enum.any?(routes, &Router.matches?(schedule.signal_type, &1.path)) do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          error("Agent schedule signal has no merged route", %{
            job_id: schedule.job_id,
            signal_type: schedule.signal_type
          })}}
      end
    end)
  end

  defp validate_extensions(extensions) do
    Enum.reduce_while(extensions, :ok, fn declaration, :ok ->
      case validate_extension(declaration) do
        :ok -> {:cont, :ok}
        {:error, validation_error} -> {:halt, {:error, validation_error}}
      end
    end)
  end

  defp validate_extension(%ExtensionDeclaration{} = declaration) do
    with :ok <- ensure_module(declaration.module, "Agent extension"),
         :ok <- ensure_behaviour(declaration.module, Jido.Agent.Extension, "Agent extension") do
      if function_exported?(declaration.module, :validate_executable, 1) do
        case declaration.module.validate_executable(declaration.data) do
          :ok ->
            :ok

          {:error, %_{} = validation_error} when is_exception(validation_error) ->
            {:error, validation_error}

          {:error, reason} ->
            {:error,
             error("Agent extension executable validation failed", %{
               extension: declaration.module,
               reason: reason
             })}

          value ->
            {:error,
             error("Agent extension executable validation returned an invalid value", %{
               extension: declaration.module,
               value: value
             })}
        end
      else
        :ok
      end
    end
  end

  defp compile_extensions(extensions) do
    Enum.reduce_while(extensions, {:ok, %{}}, fn declaration, {:ok, plans} ->
      module = declaration.module

      result =
        if function_exported?(module, :compile, 2) do
          module.compile(declaration.data, declaration.metadata)
        else
          {:ok, declaration.data}
        end

      case result do
        {:ok, %Agent{}} ->
          {:halt,
           {:error,
            error("Agent extension compilation cannot return a root Agent", %{
              extension: module
            })}}

        {:ok, plan} ->
          {:cont, {:ok, Map.put(plans, module, plan)}}

        {:error, %_{} = validation_error} when is_exception(validation_error) ->
          {:halt, {:error, validation_error}}

        {:error, reason} ->
          {:halt,
           {:error,
            error("Agent extension compilation failed", %{extension: module, reason: reason})}}

        value ->
          {:halt,
           {:error,
            error("Agent extension compilation returned an invalid value", %{
              extension: module,
              value: value
            })}}
      end
    end)
  end

  defp action_index(plugin_specs, routes) do
    actions =
      plugin_specs
      |> Enum.flat_map(& &1.actions)
      |> Kernel.++(Enum.map(routes, fn route -> elem(route_action(route.target), 1) end))
      |> Enum.uniq()

    Map.new(actions, fn action ->
      {action,
       %{
         module: action,
         name: action.name(),
         schema: action.schema(),
         output_schema: action.output_schema()
       }}
    end)
  end

  defp capability_index(instances) do
    Enum.reduce(instances, %{}, fn instance, index ->
      Enum.reduce(instance.manifest.capabilities || [], index, fn capability, acc ->
        Map.update(acc, capability, [instance.state_key], &(&1 ++ [instance.state_key]))
      end)
    end)
  end

  defp initial_state(compiled, supplied_state) do
    base_defaults = AgentState.defaults_from_schema(compiled.agent.state_schema)

    plugin_defaults =
      compiled.plugin_specs
      |> Enum.reject(&is_nil(&1.schema))
      |> Map.new(&{&1.state_key, AgentState.defaults_from_schema(&1.schema)})

    defaults = Map.merge(base_defaults, plugin_defaults)
    {:ok, AgentState.merge(defaults, supplied_state)}
  end

  defp mount_plugins(agent, instances) do
    Enum.reduce_while(instances, {:ok, agent}, fn instance, {:ok, current_agent} ->
      case instance.module.mount(current_agent, instance.config) do
        {:ok, plugin_state} when is_map(plugin_state) ->
          current_plugin_state = Map.get(current_agent.state, instance.state_key, %{})
          merged_plugin_state = Map.merge(current_plugin_state, plugin_state)
          state = Map.put(current_agent.state, instance.state_key, merged_plugin_state)
          {:cont, {:ok, %{current_agent | state: state}}}

        {:ok, nil} ->
          {:cont, {:ok, current_agent}}

        {:error, reason} ->
          {:halt,
           {:error,
            error("Agent plugin mount failed", %{plugin: instance.module, reason: reason})}}

        value ->
          {:halt,
           {:error,
            error("Agent plugin mount returned an invalid value", %{
              plugin: instance.module,
              value: value
            })}}
      end
    end)
  end

  defp validate_instance_state(state, schema) do
    case AgentState.validate(state, schema) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:error, error("Agent instance state is invalid", %{reason: reason})}
    end
  end

  defp maybe_validate_instance_state(state, schema, true),
    do: validate_instance_state(state, schema)

  defp maybe_validate_instance_state(state, _schema, false), do: {:ok, state}

  defp state_option(state) when is_map(state) and not is_struct(state), do: :ok
  defp state_option(_state), do: {:error, error("Agent instance state must be a map")}

  defp validate_state_option(value) when is_boolean(value), do: :ok

  defp validate_state_option(_value),
    do: {:error, error("Agent instance validation option must be a boolean")}

  defp instance_id(nil), do: {:ok, Jido.Util.generate_id()}
  defp instance_id(""), do: {:ok, Jido.Util.generate_id()}

  defp instance_id(id) when is_binary(id) do
    if String.valid?(id),
      do: {:ok, id},
      else: {:error, error("Agent instance ID must be valid UTF-8 text")}
  end

  defp instance_id(_id), do: {:error, error("Agent instance ID must be text")}

  defp agent_module(nil), do: {:ok, nil}

  defp agent_module(module) when is_atom(module) and module not in [true, false],
    do: {:ok, module}

  defp agent_module(_module),
    do: {:error, error("Agent module binding must be a module atom")}

  defp ensure_module(module, label) when is_atom(module) and module not in [nil, true, false] do
    case Code.ensure_compiled(module) do
      {:module, _module} ->
        :ok

      {:error, reason} ->
        {:error,
         error("#{label} module could not be compiled", %{module: module, reason: reason})}
    end
  end

  defp ensure_module(module, label),
    do: {:error, error("#{label} must be a module atom", %{module: module})}

  defp ensure_behaviour(module, behaviour, label) do
    behaviours =
      module.module_info(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()

    if behaviour in behaviours,
      do: :ok,
      else:
        {:error,
         error("#{label} module does not implement the required behaviour", %{
           module: module,
           behaviour: behaviour
         })}
  end

  defp ensure_exports(module, exports, label) do
    case Enum.find(exports, fn {name, arity} -> not function_exported?(module, name, arity) end) do
      nil ->
        :ok

      missing ->
        {:error,
         error("#{label} module is missing a required function", %{
           module: module,
           function: missing
         })}
    end
  end

  defp prefixed_path(prefix, path), do: "#{prefix}.#{path}"

  defp action_name(action) do
    action |> Module.split() |> List.last() |> Macro.underscore()
  end

  defp config_map(value, _label) when is_map(value) and not is_struct(value), do: {:ok, value}

  defp config_map(value, label) when is_list(value) do
    if Keyword.keyword?(value),
      do: {:ok, Map.new(value)},
      else: {:error, error("#{label} must be a map or keyword list")}
  end

  defp config_map(_value, label),
    do: {:error, error("#{label} must be a map or keyword list")}

  defp reverse_ok({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_ok({:error, _error} = result), do: result

  defp error(message, details \\ %{}),
    do: Error.validation_error(message, details: details)

  defp prefix_error(validation_error, path) do
    details = Map.get(validation_error, :details)

    if is_map(details) do
      %{
        validation_error
        | details: Map.put(details, :path, path ++ Map.get(details, :path, []))
      }
    else
      validation_error
    end
  end
end
