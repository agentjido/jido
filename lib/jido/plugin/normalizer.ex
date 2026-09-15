defmodule Jido.Plugin.Normalizer do
  @moduledoc false

  alias Jido.Agent.Directive
  alias Jido.Agent.Plugin.Spec, as: AgentSpec
  alias Jido.AgentServer.Plugin.Spec, as: ServerSpec
  alias Jido.Persistence.Plugin.Spec, as: PersistenceSpec
  alias Jido.Plugin.{Manifest, Spec}
  alias Jido.Plugin.Error, as: PluginError
  alias Jido.Topology.Plugin.Spec, as: TopologySpec

  @agent_callbacks [
    prepare: 2,
    state_spec: 1,
    reduce: 2,
    update_state: 3,
    directives: 1,
    validate_directive: 2
  ]
  @legacy_agent_callbacks Keyword.delete(@agent_callbacks, :reduce)
  @agent_capabilities Keyword.drop(@agent_callbacks, [:update_state, :validate_directive])

  # Authority checks keep first-error order. Capability checks only test presence.
  @server_callbacks [admit: 3, prepare_dispatch: 4, dispatch: 4, await_ready: 2, child_spec: 1]
  @persistence_callbacks [dump: 3, load: 3]
  @topology_callbacks [contribute: 2]

  # Legacy package callback order is part of first-error reporting.
  @legacy_callbacks [
    validate_options: 1,
    prepare: 2,
    child_spec: 1,
    admit: 3,
    prepare_dispatch: 4,
    state_spec: 1,
    update_state: 3,
    directives: 1,
    validate_directive: 2,
    dispatch: 4,
    await_ready: 2
  ]

  @package_callbacks [reduce: 2] ++
                       @persistence_callbacks ++ @topology_callbacks ++ @legacy_callbacks

  @doc false
  @spec normalize_all([Jido.Plugin.declaration()] | [Spec.t()]) ::
          {:ok, [Spec.t()]} | {:error, term()}
  def normalize_all(declarations) when is_list(declarations) do
    with {:ok, specs} <- normalize_specs(declarations),
         :ok <- unique_packages(specs),
         :ok <- unique_state_keys(specs),
         :ok <- unique_directives(specs) do
      {:ok, specs}
    end
  end

  def normalize_all(value),
    do: PluginError.validation("Agent Plugins must be a list", %{plugins: value})

  @doc false
  @spec canonical_declarations([Jido.Plugin.declaration()] | [Spec.t()]) ::
          {:ok, [{module(), keyword()}]} | {:error, term()}
  def canonical_declarations(declarations) do
    with {:ok, specs} <- normalize_all(declarations) do
      {:ok, Enum.map(specs, &{&1.module, &1.options})}
    end
  end

  defp normalize_specs(values) do
    {specs, declarations} = Enum.split_with(values, &match?(%Spec{}, &1))

    cond do
      declarations == [] ->
        {:ok, Enum.map(values, &upgrade_spec/1)}

      specs != [] ->
        PluginError.validation(
          "Agent Plugin declarations cannot mix normalized specs and declarations",
          %{normalized_specs: specs, declarations: declarations}
        )

      true ->
        normalize_declarations(declarations)
    end
  end

  defp normalize_declarations(declarations) do
    declarations
    |> Enum.reduce_while({:ok, []}, fn declaration, {:ok, specs} ->
      case normalize(declaration) do
        {:ok, spec} -> {:cont, {:ok, [spec | specs]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, specs} -> {:ok, Enum.reverse(specs)}
      error -> error
    end
  end

  defp upgrade_spec(%Spec{manifest: %Manifest{}} = spec), do: spec

  defp upgrade_spec(%Spec{} = spec) do
    agent =
      if has_any?(spec.module, @legacy_agent_callbacks) or not is_nil(spec.state_key) or
           spec.directive_modules != [] do
        %AgentSpec{
          package: spec.module,
          module: spec.module,
          options: spec.options,
          state_key: spec.state_key,
          state_schema: spec.state_schema,
          directive_modules: spec.directive_modules,
          legacy?: true
        }
      end

    server =
      if has_any?(spec.module, @server_callbacks) or spec.dispatch? or spec.runtime? do
        %ServerSpec{
          package: spec.module,
          module: spec.module,
          options: spec.options,
          dispatch?: spec.dispatch? or function_exported?(spec.module, :dispatch, 4),
          runtime?: spec.runtime?,
          legacy?: true
        }
      end

    manifest = %Manifest{
      module: spec.module,
      agent: facet_module(agent),
      agent_server: facet_module(server)
    }

    %{
      spec
      | manifest: manifest,
        agent: agent,
        agent_server: server,
        legacy?: true,
        dispatch?: not is_nil(server) and server.dispatch?,
        runtime?: not is_nil(server) and server.runtime?
    }
  end

  defp normalize(module) when is_atom(module), do: build_spec(module, [])

  defp normalize({module, options}) when is_atom(module) and is_list(options) do
    if Keyword.keyword?(options) do
      build_spec(module, options)
    else
      PluginError.validation("Agent Plugin options must be a keyword list", %{
        plugin: module,
        options: options
      })
    end
  end

  defp normalize(declaration),
    do: PluginError.validation("Invalid Agent Plugin declaration", %{plugin: declaration})

  defp build_spec(module, options) do
    with :ok <- ensure_loaded(module),
         {:ok, marker} <- read_package_marker(module) do
      case marker do
        :agent -> build_legacy_spec(module, options)
        %Manifest{} = manifest -> build_manifest_spec(module, options, manifest)
        _marker -> invalid_package(module)
      end
    end
  end

  defp build_legacy_spec(module, options) do
    with :ok <- validate_legacy_contract(module),
         :ok <- legacy_has_capability(module),
         {:ok, options} <- read_legacy_options(module, options),
         {:ok, agent} <- build_legacy_agent_spec(module, options),
         {:ok, server} <- build_legacy_server_spec(module, options),
         :ok <- validate_pair(module, agent, server, nil, nil) do
      manifest = %Manifest{
        module: module,
        agent: facet_module(agent),
        agent_server: facet_module(server)
      }

      {:ok, aggregate(module, options, manifest, agent, server, nil, nil, true)}
    end
  end

  defp build_manifest_spec(module, options, %Manifest{} = manifest) do
    with true <- manifest.module == module,
         {:ok, manifest} <- Manifest.validate(manifest, options),
         :ok <- callback_free_package(module),
         {:ok, agent} <- build_agent_spec(manifest, options),
         {:ok, server} <- build_server_spec(manifest, options),
         {:ok, persistence} <- build_persistence_spec(manifest, options),
         {:ok, topology} <- build_topology_spec(manifest, options),
         :ok <- validate_pair(module, agent, server, persistence, topology) do
      {:ok,
       aggregate(
         module,
         options,
         manifest,
         agent,
         server,
         persistence,
         topology,
         false
       )}
    else
      false ->
        PluginError.validation("Plugin manifest package module does not match", %{
          plugin: module,
          manifest: manifest.module
        })

      {:error, _reason} = error ->
        error
    end
  end

  defp build_legacy_agent_spec(module, options) do
    if has_any?(module, @legacy_agent_callbacks) do
      build_agent_values(module, module, options, true)
    else
      {:ok, nil}
    end
  end

  defp build_legacy_server_spec(module, options) do
    if has_any?(module, @server_callbacks) do
      {:ok,
       %ServerSpec{
         package: module,
         module: module,
         options: options,
         dispatch?: function_exported?(module, :dispatch, 4),
         runtime?: function_exported?(module, :child_spec, 1),
         legacy?: true
       }}
    else
      {:ok, nil}
    end
  end

  defp build_agent_spec(%Manifest{agent: nil}, _options), do: {:ok, nil}

  defp build_agent_spec(%Manifest{} = manifest, options) do
    facet = manifest.agent
    facet_options = Manifest.options_for(manifest, :agent, options)

    with :ok <- validate_facet(facet, Jido.Agent.Plugin, :agent),
         :ok <- facet_has_capability(facet, :agent),
         do: build_agent_values(manifest.module, facet, facet_options, false)
  end

  defp build_agent_values(package, facet, options, legacy?) do
    with {:ok, {state_key, state_schema}} <- read_state_spec(package, facet, options),
         {:ok, directive_modules} <- read_directives(package, facet, options),
         :ok <-
           validate_agent_contract(package, facet, state_key, directive_modules, legacy?) do
      {:ok,
       %AgentSpec{
         package: package,
         module: facet,
         options: options,
         state_key: state_key,
         state_schema: state_schema,
         directive_modules: directive_modules,
         legacy?: legacy?
       }}
    end
  end

  defp build_server_spec(%Manifest{agent_server: nil}, _options), do: {:ok, nil}

  defp build_server_spec(%Manifest{} = manifest, options) do
    facet = manifest.agent_server
    facet_options = Manifest.options_for(manifest, :agent_server, options)

    with :ok <- validate_facet(facet, Jido.AgentServer.Plugin, :agent_server),
         :ok <- facet_has_capability(facet, :agent_server) do
      {:ok,
       %ServerSpec{
         package: manifest.module,
         module: facet,
         options: facet_options,
         dispatch?: function_exported?(facet, :dispatch, 4),
         runtime?: function_exported?(facet, :child_spec, 1),
         legacy?: false
       }}
    end
  end

  defp build_persistence_spec(%Manifest{persistence: nil}, _options), do: {:ok, nil}

  defp build_persistence_spec(%Manifest{} = manifest, options) do
    facet = manifest.persistence

    with :ok <- validate_facet(facet, Jido.Persistence.Plugin, :persistence),
         true <- function_exported?(facet, :dump, 3) and function_exported?(facet, :load, 3) do
      {:ok,
       %PersistenceSpec{
         package: manifest.module,
         module: facet,
         options: Manifest.options_for(manifest, :persistence, options),
         vsn: manifest.vsn
       }}
    else
      false ->
        PluginError.validation("Persistence Plugin facet must define dump/3 and load/3", %{
          plugin: manifest.module,
          facet: facet
        })

      {:error, _reason} = error ->
        error
    end
  end

  defp build_topology_spec(%Manifest{topology: nil}, _options), do: {:ok, nil}

  defp build_topology_spec(%Manifest{} = manifest, options) do
    facet = manifest.topology

    with :ok <- validate_facet(facet, Jido.Topology.Plugin, :topology),
         true <- function_exported?(facet, :contribute, 2) do
      {:ok,
       %TopologySpec{
         package: manifest.module,
         module: facet,
         options: Manifest.options_for(manifest, :topology, options),
         vsn: manifest.vsn
       }}
    else
      false ->
        PluginError.validation("Topology Plugin facet must define contribute/2", %{
          plugin: manifest.module,
          facet: facet
        })

      {:error, _reason} = error ->
        error
    end
  end

  defp validate_pair(package, agent, server, persistence, _topology) do
    cond do
      not is_nil(persistence) and (is_nil(agent) or is_nil(agent.state_key)) ->
        PluginError.validation("Persistence Plugin facet requires a stateful Agent facet", %{
          plugin: package
        })

      not is_nil(server) and server.dispatch? and
          (is_nil(agent) or agent.directive_modules == []) ->
        message =
          if server.legacy?,
            do: "Agent Plugin dispatch/4 requires declared Directives",
            else: "Agent Server Plugin dispatch requires Agent-owned Directives"

        PluginError.validation(message, %{plugin: package, facet: server.module})

      not is_nil(agent) and agent.directive_modules != [] and
        not reducer?(agent) and
          (is_nil(server) or not server.dispatch?) ->
        PluginError.validation(
          "Agent Plugin Directives must reduce state or dispatch runtime work",
          %{plugin: package}
        )

      true ->
        :ok
    end
  end

  defp read_package_marker(module) do
    if function_exported?(module, :__jido_plugin__, 0) do
      case PluginError.safe_apply(
             module,
             module,
             :__jido_plugin__,
             [],
             "Agent Plugin marker failed"
           ) do
        {:error, _reason} = error -> error
        marker -> {:ok, marker}
      end
    else
      {:ok, :missing}
    end
  end

  defp validate_legacy_contract(module) do
    behaviours = behaviours(module)

    if Jido.Plugin in behaviours do
      :ok
    else
      invalid_package(module)
    end
  end

  defp invalid_package(module),
    do: PluginError.validation("Agent Plugin must use Jido.Plugin", %{plugin: module})

  defp callback_free_package(module) do
    case Enum.find(@package_callbacks, fn {function, arity} ->
           function_exported?(module, function, arity)
         end) do
      nil ->
        :ok

      callback ->
        PluginError.validation("Plugin package manifest must not define facet callbacks", %{
          plugin: module,
          callback: callback
        })
    end
  end

  defp validate_facet(module, behaviour, owner) do
    with :ok <- ensure_loaded(module),
         true <- behaviour in behaviours(module),
         true <- function_exported?(module, :__jido_plugin_facet__, 0),
         ^owner <- module.__jido_plugin_facet__(),
         :ok <- validate_facet_authority(module, owner) do
      :ok
    else
      {:error, _reason} = error ->
        error

      _value ->
        PluginError.validation("Plugin facet must use its owner behavior", %{
          facet: module,
          owner: owner,
          behaviour: behaviour
        })
    end
  rescue
    error ->
      PluginError.validation("Plugin facet metadata failed", %{
        facet: module,
        owner: owner,
        error: error
      })
  catch
    kind, reason ->
      PluginError.validation("Plugin facet metadata failed", %{
        facet: module,
        owner: owner,
        kind: kind,
        reason: reason
      })
  end

  defp validate_facet_authority(module, owner) do
    foreign =
      case owner do
        :agent -> @server_callbacks ++ @persistence_callbacks ++ @topology_callbacks
        :agent_server -> @agent_callbacks ++ @persistence_callbacks ++ @topology_callbacks
        :persistence -> @agent_callbacks ++ @server_callbacks ++ @topology_callbacks
        :topology -> @agent_callbacks ++ @server_callbacks ++ @persistence_callbacks
      end

    case Enum.find(foreign, fn {function, arity} ->
           function_exported?(module, function, arity)
         end) do
      nil ->
        :ok

      callback ->
        PluginError.validation("Plugin facet defines a callback owned by another facet", %{
          facet: module,
          owner: owner,
          callback: callback
        })
    end
  end

  defp facet_has_capability(module, :agent),
    do: require_capability(module, :agent, @agent_capabilities)

  defp facet_has_capability(module, :agent_server),
    do: require_capability(module, :agent_server, @server_callbacks)

  defp require_capability(module, owner, callbacks) do
    if has_any?(module, callbacks) do
      :ok
    else
      PluginError.validation("Plugin facet defines no capability", %{
        facet: module,
        owner: owner
      })
    end
  end

  defp read_legacy_options(module, options) do
    if function_exported?(module, :validate_options, 1) do
      PluginError.safe_apply(
        module,
        module,
        :validate_options,
        [options],
        "Agent Plugin validate_options/1 failed"
      )
      |> validate_options_result(module, options)
    else
      {:ok, options}
    end
  end

  defp validate_options_result(:ok, _module, options), do: {:ok, options}

  defp validate_options_result({:ok, validated}, module, _options)
       when is_list(validated) do
    if Keyword.keyword?(validated),
      do: {:ok, validated},
      else:
        PluginError.validation("Agent Plugin validate_options/1 returned invalid options", %{
          plugin: module,
          options: validated
        })
  end

  defp validate_options_result({:error, _reason} = error, _module, _options), do: error

  defp validate_options_result({:ok, validated}, module, _options) do
    PluginError.validation("Agent Plugin validate_options/1 returned invalid options", %{
      plugin: module,
      options: validated
    })
  end

  defp validate_options_result(result, module, _options) do
    PluginError.invalid_callback(
      "Agent Plugin validate_options/1 returned an invalid result",
      module,
      module,
      %{result: result}
    )
  end

  defp legacy_has_capability(module) do
    if has_any?(module, Keyword.delete(@legacy_callbacks, :validate_options)) do
      :ok
    else
      PluginError.validation("Agent Plugin defines no capability", %{plugin: module})
    end
  end

  defp read_state_spec(package, facet, options) do
    if function_exported?(facet, :state_spec, 1) do
      PluginError.safe_apply(
        package,
        facet,
        :state_spec,
        [options],
        "Agent Plugin state_spec/1 failed"
      )
      |> validate_state_spec(package, facet)
    else
      {:ok, {nil, nil}}
    end
  end

  defp validate_state_spec(:none, _package, _facet), do: {:ok, {nil, nil}}

  defp validate_state_spec({:error, reason} = error, _package, _facet)
       when is_exception(reason),
       do: error

  defp validate_state_spec({nil, _schema}, package, facet) do
    PluginError.validation("Plugin-owned Agent state key must not be nil", %{
      plugin: package,
      facet: facet,
      state_key: nil
    })
  end

  defp validate_state_spec({:__struct__, _schema}, package, facet) do
    PluginError.validation("Plugin-owned Agent state key is reserved", %{
      plugin: package,
      facet: facet,
      state_key: :__struct__
    })
  end

  defp validate_state_spec({key, schema}, package, facet)
       when is_atom(key) and not is_nil(key) and key != :__struct__ and is_struct(schema) do
    cond do
      is_nil(Zoi.Type.impl_for(schema)) ->
        PluginError.validation("Plugin-owned Agent state schema must be a Zoi schema", %{
          plugin: package,
          facet: facet,
          schema: schema
        })

      true ->
        case Jido.Action.validate_static_data(schema) do
          :ok ->
            {:ok, {key, schema}}

          {:error, reason} ->
            PluginError.validation("Plugin-owned Agent state schema must contain static data", %{
              plugin: package,
              facet: facet,
              state_key: key,
              reason: reason
            })
        end
    end
  end

  defp validate_state_spec(value, package, facet) do
    PluginError.validation("Agent Plugin state_spec/1 returned an invalid value", %{
      plugin: package,
      facet: facet,
      value: value
    })
  end

  defp read_directives(package, facet, options) do
    result =
      if function_exported?(facet, :directives, 1) do
        PluginError.safe_apply(
          package,
          facet,
          :directives,
          [options],
          "Agent Plugin directives/1 failed"
        )
      else
        []
      end

    validate_directive_modules(result, package, facet)
  end

  defp validate_directive_modules({:error, _reason} = error, _package, _facet), do: error

  defp validate_directive_modules(directives, package, facet) when is_list(directives) do
    atom_modules? = Enum.all?(directives, &is_atom/1)
    unloaded = if atom_modules?, do: first_invalid(directives, &(not Code.ensure_loaded?(&1)))

    not_struct =
      if atom_modules? and unloaded == nil,
        do: first_invalid(directives, &(not function_exported?(&1, :__struct__, 0)))

    cond do
      not atom_modules? ->
        PluginError.validation("Agent Plugin Directive modules must be atoms", %{
          plugin: package,
          facet: facet,
          directives: directives
        })

      Enum.uniq(directives) != directives ->
        PluginError.validation("Agent Plugin Directive modules must be unique", %{
          plugin: package,
          facet: facet,
          directives: directives
        })

      unloaded != nil ->
        PluginError.validation("Agent Plugin Directive modules must be loaded", %{
          plugin: package,
          facet: facet,
          directive: elem(unloaded, 1)
        })

      not_struct != nil ->
        PluginError.validation("Agent Plugin Directive modules must define a struct", %{
          plugin: package,
          facet: facet,
          directive: elem(not_struct, 1)
        })

      Enum.any?(directives, &Directive.built_in_module?/1) ->
        PluginError.validation("Agent Plugin cannot own a built-in Directive", %{
          plugin: package,
          facet: facet
        })

      true ->
        {:ok, directives}
    end
  end

  defp validate_directive_modules(value, package, facet) do
    PluginError.validation("Agent Plugin directives/1 must return a list", %{
      plugin: package,
      facet: facet,
      directives: value
    })
  end

  defp first_invalid(values, predicate) do
    Enum.find_value(values, fn value -> if predicate.(value), do: {:invalid, value} end)
  end

  defp validate_agent_contract(package, facet, state_key, directives, true) do
    validates? = function_exported?(facet, :validate_directive, 2)
    updates? = function_exported?(facet, :update_state, 3)

    cond do
      directives != [] and not validates? ->
        PluginError.validation("Agent Plugin with Directives must define validate_directive/2", %{
          plugin: package,
          facet: facet
        })

      updates? and is_nil(state_key) ->
        PluginError.validation("Agent Plugin update_state/3 requires state_spec/1", %{
          plugin: package,
          facet: facet
        })

      true ->
        :ok
    end
  end

  defp validate_agent_contract(package, facet, state_key, directives, false) do
    reducer? = function_exported?(facet, :reduce, 2)
    invalid_directive = Enum.find(directives, &(not Directive.validator?(&1)))

    cond do
      function_exported?(facet, :validate_directive, 2) ->
        PluginError.validation(
          "Agent Plugin Directive validation belongs to the Directive module",
          %{plugin: package, facet: facet, callback: {:validate_directive, 2}}
        )

      function_exported?(facet, :update_state, 3) ->
        PluginError.validation("Agent Plugin state middleware must define reduce/2", %{
          plugin: package,
          facet: facet,
          callback: {:update_state, 3}
        })

      invalid_directive ->
        PluginError.validation("Agent Plugin Directive must define validate/1", %{
          plugin: package,
          facet: facet,
          directive: invalid_directive
        })

      reducer? and is_nil(state_key) ->
        PluginError.validation("Agent Plugin reduce/2 requires state_spec/1", %{
          plugin: package,
          facet: facet
        })

      true ->
        :ok
    end
  end

  defp reducer?(%AgentSpec{legacy?: true, module: module}),
    do: function_exported?(module, :update_state, 3)

  defp reducer?(%AgentSpec{module: module}), do: function_exported?(module, :reduce, 2)

  defp unique_packages(specs) do
    unique_by(specs, & &1.module, "Agent Plugin modules must be unique", :plugin)
  end

  defp unique_state_keys(specs) do
    specs
    |> Enum.reject(&(is_nil(&1.agent) or is_nil(&1.agent.state_key)))
    |> unique_by(& &1.agent.state_key, "Plugin-owned Agent state keys must be unique", :state_key)
  end

  defp unique_directives(specs) do
    specs
    |> Enum.flat_map(fn spec ->
      case spec.agent do
        %AgentSpec{} = agent -> Enum.map(agent.directive_modules, &{&1, spec.module})
        nil -> []
      end
    end)
    |> unique_by(&elem(&1, 0), "Agent Plugin Directive ownership must be unique", :directive)
  end

  defp unique_by(values, key_fun, message, detail_key) do
    case values
         |> Enum.group_by(key_fun)
         |> Enum.find(fn {_key, group} -> match?([_first, _second | _rest], group) end) do
      nil -> :ok
      {key, group} -> PluginError.validation(message, %{detail_key => key, declarations: group})
    end
  end

  defp aggregate(module, options, manifest, agent, server, persistence, topology, legacy?) do
    %Spec{
      module: module,
      options: options,
      manifest: manifest,
      agent: agent,
      agent_server: server,
      persistence: persistence,
      topology: topology,
      legacy?: legacy?,
      state_key: field(agent, :state_key),
      state_schema: field(agent, :state_schema),
      directive_modules: field(agent, :directive_modules, []),
      dispatch?: not is_nil(server) and server.dispatch?,
      runtime?: not is_nil(server) and server.runtime?
    }
  end

  defp field(nil, _field), do: nil
  defp field(value, field), do: Map.fetch!(value, field)
  defp field(nil, _field, default), do: default
  defp field(value, field, _default), do: Map.fetch!(value, field)

  defp facet_module(nil), do: nil
  defp facet_module(spec), do: spec.module

  defp behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end

  defp ensure_loaded(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        :ok

      {:error, reason} ->
        PluginError.validation("Agent Plugin could not be loaded", %{
          plugin: module,
          reason: reason
        })
    end
  end

  defp has_any?(module, callbacks) do
    Enum.any?(callbacks, fn {function, arity} -> function_exported?(module, function, arity) end)
  end
end
