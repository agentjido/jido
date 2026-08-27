defmodule Jido.Agent.Codec do
  @moduledoc """
  Encodes and decodes the versioned neutral Agent definition document.

  The codec accepts JSON-compatible Elixir terms. It does not parse or emit
  JSON bytes. A trusted `Jido.Agent.Registry` resolves every stored module,
  schema, function capture, and atom identifier.
  """

  alias Jido.Agent
  alias Jido.Agent.Data
  alias Jido.Agent.Extension.Declaration, as: ExtensionDeclaration
  alias Jido.Agent.Plugin
  alias Jido.Agent.PluginDefaults
  alias Jido.Agent.Registry
  alias Jido.Agent.Schedule
  alias Jido.Error
  alias Jido.Signal.Router.Route

  @type document :: %{required(String.t()) => term()}

  @version 1
  @maximum_depth 100
  @maximum_collection_size 10_000
  @maximum_document_nodes 100_000

  @root_keys [
    "type",
    "version",
    "name",
    "description",
    "state_schema",
    "plugin_defaults",
    "plugins",
    "routes",
    "schedules",
    "extensions",
    "metadata"
  ]

  @doc "Encodes one neutral Agent definition with a generated Registry."
  @spec encode(Agent.t()) ::
          {:ok, document(), Registry.t()} | {:error, Exception.t()}
  def encode(%Agent{} = agent) do
    with :ok <- definition_only(agent),
         {:ok, registry} <- Registry.from_agent(agent),
         {:ok, document} <- encode(agent, registry) do
      {:ok, document, registry}
    end
  end

  def encode(value), do: {:error, error("expected a Jido.Agent value", %{value: value})}

  @doc "Encodes one neutral Agent definition through a supplied Registry."
  @spec encode(Agent.t(), Registry.t()) :: {:ok, document()} | {:error, Exception.t()}
  def encode(%Agent{} = agent, %Registry{} = registry) do
    with :ok <- definition_only(agent),
         {:ok, agent} <- Agent.validate(agent),
         {:ok, state_schema} <- Registry.identifier(registry, :schema, agent.state_schema),
         {:ok, plugin_defaults} <- encode_plugin_defaults(agent.plugin_defaults, registry),
         {:ok, plugins} <- encode_sequence(agent.plugins, "plugins", registry, &encode_plugin/2),
         {:ok, routes} <- encode_sequence(agent.routes, "routes", registry, &encode_route/2),
         {:ok, schedules} <-
           encode_sequence(agent.schedules, "schedules", registry, &encode_schedule/2),
         {:ok, extensions} <-
           encode_sequence(agent.extensions, "extensions", registry, &encode_extension/2),
         {:ok, metadata} <- encode_data(agent.metadata, registry, 0) do
      document = %{
        "type" => "jido.agent",
        "version" => @version,
        "name" => agent.name,
        "description" => agent.description,
        "state_schema" => state_schema,
        "plugin_defaults" => plugin_defaults,
        "plugins" => plugins,
        "routes" => routes,
        "schedules" => schedules,
        "extensions" => extensions,
        "metadata" => metadata
      }

      with :ok <- validate_document_limits(document), do: {:ok, document}
    end
  end

  def encode(%Agent{}, registry) do
    {:error, error("Agent codec registry must be a Jido.Agent.Registry", %{value: registry})}
  end

  def encode(value, %Registry{}) do
    {:error, error("expected a Jido.Agent value", %{value: value})}
  end

  def encode(value, registry) do
    {:error,
     error("Agent codec registry must be a Jido.Agent.Registry", %{
       value: registry,
       agent: value
     })}
  end

  @doc "Decodes one stored Agent definition and returns the first error."
  @spec decode(document(), Registry.t()) :: {:ok, Agent.t()} | {:error, Exception.t()}
  def decode(document, registry) do
    case diagnose(document, registry) do
      {:ok, agent} -> {:ok, agent}
      {:error, %Error.Invalid{errors: [first | _rest]}} -> {:error, first}
    end
  end

  @doc "Diagnoses one complete stored Agent definition without returning partial data."
  @spec diagnose(document(), Registry.t()) ::
          {:ok, Agent.t()} | {:error, Error.Invalid.t()}
  def diagnose(document, %Registry{} = registry)
      when is_map(document) and not is_struct(document) do
    case validate_document_limits(document) do
      :ok -> diagnose_safe_document(document, registry)
      {:error, validation_error} -> diagnostic_failure([validation_error])
    end
  end

  def diagnose(document, %Registry{}) do
    diagnostic_failure([
      error("stored Agent document must be a map", %{value: document})
    ])
  end

  def diagnose(_document, registry) do
    diagnostic_failure([
      error("Agent codec registry must be a Jido.Agent.Registry", %{value: registry})
    ])
  end

  defp diagnose_safe_document(document, registry) do
    case diagnose_envelope(document) do
      [] -> diagnose_document(document, registry)
      errors -> diagnostic_failure(errors)
    end
  end

  defp definition_only(%Agent{id: nil, state: nil, agent_module: nil}), do: :ok

  defp definition_only(%Agent{} = agent) do
    populated =
      [:id, :state, :agent_module]
      |> Enum.filter(&(not is_nil(Map.fetch!(agent, &1))))

    {:error,
     error("Agent Codec accepts definition-only values", %{
       path: Enum.map(populated, &Atom.to_string/1),
       fields: populated
     })}
  end

  defp diagnose_envelope(document) do
    unknown_field_errors(document, @root_keys, []) ++
      result_errors(exact_value(document, "type", "jido.agent", [])) ++
      result_errors(exact_value(document, "version", @version, []))
  end

  defp diagnose_document(document, registry) do
    fields = [
      name: fn -> string_field(document, "name", []) end,
      description: fn -> optional_string_field(document, "description", []) end,
      state_schema: fn -> resolve_field(document, "state_schema", :schema, registry, []) end,
      plugin_defaults: fn -> diagnose_plugin_defaults_field(document, registry) end,
      plugins: fn -> diagnose_plugins_field(document, registry) end,
      routes: fn -> diagnose_routes_field(document, registry) end,
      schedules: fn -> diagnose_schedules_field(document, registry) end,
      extensions: fn -> diagnose_extensions_field(document, registry) end,
      metadata: fn -> diagnose_data_object_field(document, "metadata", registry, []) end
    ]

    case collect_values(fields) do
      {:ok, attrs} ->
        case diagnose_constructor(Agent.new(attrs), []) do
          {:ok, agent} -> {:ok, agent}
          {:error, validation_error} -> diagnostic_failure([validation_error])
        end

      {:error, errors} ->
        diagnostic_failure(errors)
    end
  end

  defp diagnose_plugin_defaults_field(document, registry) do
    case Map.fetch(document, "plugin_defaults") do
      {:ok, value} -> diagnose_plugin_defaults(value, registry, ["plugin_defaults"])
      :error -> required_field(["plugin_defaults"], "plugin_defaults")
    end
  end

  defp diagnose_plugin_defaults(%{} = record, registry, path) when not is_struct(record) do
    fields = [
      mode: fn -> diagnose_plugin_default_mode(record, path) end,
      overrides: fn -> diagnose_plugin_default_overrides(record, registry, path) end
    ]

    errors = unknown_field_errors(record, ["mode", "overrides"], path)

    case collect_values(fields, errors) do
      {:ok, attrs} -> diagnose_constructor(PluginDefaults.new(attrs), path)
      {:error, nested} -> {:error, nested}
    end
  end

  defp diagnose_plugin_defaults(_value, _registry, path) do
    {:error, error("stored Agent plugin-default policy must be a map", %{path: path})}
  end

  defp diagnose_plugin_default_mode(record, path) do
    with {:ok, mode} <- string_field(record, "mode", path) do
      case mode do
        "inherit" -> {:ok, :inherit}
        "none" -> {:ok, :none}
        _other -> {:error, error("unsupported plugin-default mode", %{path: path ++ ["mode"]})}
      end
    end
  end

  defp diagnose_plugin_default_overrides(record, registry, path) do
    case Map.fetch(record, "overrides") do
      {:ok, values} when is_list(values) ->
        diagnose_plugin_default_override_list(values, registry, path)

      {:ok, _value} ->
        {:error,
         error("stored Agent plugin-default overrides must be a list", %{
           path: path ++ ["overrides"]
         })}

      :error ->
        required_field(path ++ ["overrides"], "overrides")
    end
  end

  defp diagnose_plugin_default_override_list(values, registry, path) do
    overrides_path = path ++ ["overrides"]

    with :ok <- ensure_collection_size(values, overrides_path),
         {:ok, entries} <-
           values
           |> Enum.with_index()
           |> collect_sequence(fn {value, index} ->
             diagnose_plugin_default_override(
               value,
               registry,
               overrides_path ++ [index],
               index
             )
           end) do
      diagnose_override_entries(entries, overrides_path)
    end
  end

  defp diagnose_plugin_default_override(%{} = record, registry, path, index)
       when not is_struct(record) do
    fields = [
      state_key: fn -> resolve_field(record, "state_key", :atom, registry, path) end,
      plugin: fn -> diagnose_optional_plugin_field(record, "plugin", registry, path) end
    ]

    errors = unknown_field_errors(record, ["state_key", "plugin"], path)

    case collect_values(fields, errors) do
      {:ok, %{state_key: state_key, plugin: plugin}} ->
        value = if is_nil(plugin), do: :disabled, else: plugin
        {:ok, %{index: index, key: state_key, value: value}}

      {:error, nested} ->
        {:error, nested}
    end
  end

  defp diagnose_plugin_default_override(_value, _registry, path, _index) do
    {:error, error("stored Agent plugin-default override must be a map", %{path: path})}
  end

  defp diagnose_override_entries(entries, path) do
    {overrides, errors} =
      Enum.reduce(entries, {%{}, []}, fn %{index: index, key: key, value: value},
                                         {overrides, errors} ->
        if Map.has_key?(overrides, key) do
          duplicate =
            error("stored Agent plugin-default policy contains a duplicate state key", %{
              path: path ++ [index, "state_key"]
            })

          {overrides, [duplicate | errors]}
        else
          {Map.put(overrides, key, value), errors}
        end
      end)

    if errors == [], do: {:ok, overrides}, else: {:error, Enum.reverse(errors)}
  end

  defp diagnose_plugins_field(document, registry) do
    diagnose_record_list_field(document, "plugins", registry, [], &diagnose_plugin/3)
  end

  defp diagnose_optional_plugin_field(record, field, registry, path) do
    case Map.fetch(record, field) do
      {:ok, nil} -> {:ok, nil}
      {:ok, value} -> diagnose_plugin(value, registry, path ++ [field])
      :error -> required_field(path ++ [field], field)
    end
  end

  defp diagnose_plugin(%{} = record, registry, path) when not is_struct(record) do
    fields = [
      module: fn -> resolve_field(record, "module", :plugin, registry, path) end,
      as: fn -> resolve_optional_field(record, "as", :atom, registry, path) end,
      config: fn -> diagnose_data_object_field(record, "config", registry, path) end,
      metadata: fn -> diagnose_data_object_field(record, "metadata", registry, path) end
    ]

    errors = unknown_field_errors(record, ["module", "as", "config", "metadata"], path)

    case collect_values(fields, errors) do
      {:ok, attrs} -> diagnose_constructor(Plugin.new(attrs), path)
      {:error, nested} -> {:error, nested}
    end
  end

  defp diagnose_plugin(_value, _registry, path) do
    {:error, error("stored Agent plugin declaration must be a map", %{path: path})}
  end

  defp diagnose_routes_field(document, registry) do
    diagnose_record_list_field(document, "routes", registry, [], &diagnose_route/3)
  end

  defp diagnose_route(%{} = record, registry, path) when not is_struct(record) do
    fields = [
      path: fn -> diagnose_route_path(record, path) end,
      action: fn -> resolve_field(record, "action", :action, registry, path) end,
      params: fn -> diagnose_route_params(record, registry, path) end,
      match: fn -> resolve_optional_field(record, "match", :route_match, registry, path) end,
      priority: fn -> diagnose_route_priority(record, path) end
    ]

    errors =
      unknown_field_errors(record, ["path", "action", "params", "match", "priority"], path)

    case collect_values(fields, errors) do
      {:ok, attrs} ->
        target = if is_nil(attrs.params), do: attrs.action, else: {attrs.action, attrs.params}

        {:ok,
         %Route{
           path: attrs.path,
           target: target,
           match: attrs.match,
           priority: attrs.priority
         }}

      {:error, nested} ->
        {:error, nested}
    end
  end

  defp diagnose_route(_value, _registry, path) do
    {:error, error("stored Agent route declaration must be a map", %{path: path})}
  end

  defp diagnose_route_path(record, path) do
    with {:ok, value} <- string_field(record, "path", path),
         :ok <- Route.validate_path(value, []) do
      {:ok, value}
    else
      {:error, message} when is_binary(message) ->
        {:error, error(message, %{path: path ++ ["path"]})}

      {:error, validation_error} ->
        {:error, validation_error}
    end
  end

  defp diagnose_route_params(record, registry, path) do
    case Map.fetch(record, "params") do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, value} ->
        with {:ok, params} <- diagnose_data(value, registry, 0, path ++ ["params"]),
             :ok <- Data.validate_object(params) do
          {:ok, params}
        else
          {:error, validation_error} ->
            {:error, ensure_json_path(validation_error, path ++ ["params"])}
        end

      :error ->
        required_field(path ++ ["params"], "params")
    end
  end

  defp diagnose_route_priority(record, path) do
    case Map.fetch(record, "priority") do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, value} when is_integer(value) and value in -100..100 ->
        {:ok, value}

      {:ok, _value} ->
        {:error,
         error("stored Agent route priority must be an integer from -100 through 100", %{
           path: path ++ ["priority"]
         })}

      :error ->
        required_field(path ++ ["priority"], "priority")
    end
  end

  defp diagnose_schedules_field(document, registry) do
    diagnose_record_list_field(document, "schedules", registry, [], &diagnose_schedule/3)
  end

  defp diagnose_schedule(%{} = record, registry, path) when not is_struct(record) do
    fields = [
      name: fn -> string_field(record, "name", path) end,
      cron_expression: fn -> string_field(record, "cron_expression", path) end,
      signal_type: fn -> string_field(record, "signal_type", path) end,
      timezone: fn -> string_field(record, "timezone", path) end,
      data: fn -> diagnose_data_object_field(record, "data", registry, path) end,
      metadata: fn -> diagnose_data_object_field(record, "metadata", registry, path) end
    ]

    allowed = ["name", "cron_expression", "signal_type", "timezone", "data", "metadata"]
    errors = unknown_field_errors(record, allowed, path)

    case collect_values(fields, errors) do
      {:ok, attrs} -> diagnose_constructor(Schedule.new(attrs), path)
      {:error, nested} -> {:error, nested}
    end
  end

  defp diagnose_schedule(_value, _registry, path) do
    {:error, error("stored Agent schedule declaration must be a map", %{path: path})}
  end

  defp diagnose_extensions_field(document, registry) do
    diagnose_record_list_field(document, "extensions", registry, [], &diagnose_extension/3)
  end

  defp diagnose_extension(%{} = record, registry, path) when not is_struct(record) do
    errors = unknown_field_errors(record, ["module", "data", "metadata"], path)

    case resolve_field(record, "module", :extension, registry, path) do
      {:ok, module} ->
        fields = [
          data: fn -> diagnose_extension_data(record, module, registry, path) end,
          metadata: fn -> diagnose_data_object_field(record, "metadata", registry, path) end
        ]

        case collect_values(fields, errors) do
          {:ok, attrs} ->
            attrs
            |> Map.put(:module, module)
            |> ExtensionDeclaration.new()
            |> diagnose_constructor(path)

          {:error, nested} ->
            {:error, nested}
        end

      {:error, module_error} ->
        data_errors =
          if Map.has_key?(record, "data"),
            do: [],
            else: [
              error("stored Agent field is required", %{path: path ++ ["data"], field: "data"})
            ]

        metadata_errors =
          case diagnose_data_object_field(record, "metadata", registry, path) do
            {:ok, _metadata} -> []
            {:error, nested} when is_list(nested) -> nested
            {:error, validation_error} -> [validation_error]
          end

        {:error, errors ++ [module_error] ++ data_errors ++ metadata_errors}
    end
  end

  defp diagnose_extension(_value, _registry, path) do
    {:error, error("stored Agent extension declaration must be a map", %{path: path})}
  end

  defp diagnose_extension_data(record, module, registry, path) do
    case Map.fetch(record, "data") do
      {:ok, document_data} ->
        data_path = path ++ ["data"]

        case Code.ensure_loaded(module) do
          {:module, ^module} ->
            if function_exported?(module, :decode, 2) do
              module
              |> invoke_extension_codec(:decode, [document_data, registry])
              |> extension_decode_result(module, data_path)
            else
              diagnose_data(document_data, registry, 0, data_path)
            end

          {:error, reason} ->
            {:error,
             error("trusted Agent extension module could not be loaded", %{
               extension: module,
               reason: reason,
               path: data_path
             })}
        end

      :error ->
        required_field(path ++ ["data"], "data")
    end
  end

  defp extension_decode_result({:ok, %Agent{}}, module, path) do
    {:error,
     error("Agent extension decode cannot return a root Agent", %{
       extension: module,
       path: path
     })}
  end

  defp extension_decode_result({:ok, data}, _module, _path), do: {:ok, data}

  defp extension_decode_result({:error, %_{} = validation_error}, _module, path)
       when is_exception(validation_error),
       do: {:error, ensure_json_path(validation_error, path)}

  defp extension_decode_result({:error, reason}, module, path) do
    {:error,
     error("Agent extension decode failed", %{
       extension: module,
       reason: reason,
       path: path
     })}
  end

  defp extension_decode_result(value, module, path) do
    {:error,
     error("Agent extension decode returned an invalid value", %{
       extension: module,
       value: value,
       path: path
     })}
  end

  defp diagnose_record_list_field(record, field, registry, path, decoder) do
    case Map.fetch(record, field) do
      {:ok, values} when is_list(values) ->
        diagnose_record_list(values, field, registry, path, decoder)

      {:ok, _value} ->
        {:error, error("stored Agent field must be a list", %{path: path ++ [field]})}

      :error ->
        required_field(path ++ [field], field)
    end
  end

  defp diagnose_record_list(values, field, registry, path, decoder) do
    list_path = path ++ [field]

    with :ok <- ensure_collection_size(values, list_path) do
      values
      |> Enum.with_index()
      |> collect_sequence(fn {value, index} ->
        decoder.(value, registry, list_path ++ [index])
      end)
    end
  end

  defp diagnose_data_object_field(record, field, registry, path) do
    case Map.fetch(record, field) do
      {:ok, value} ->
        with {:ok, decoded} <- diagnose_data(value, registry, 0, path ++ [field]),
             :ok <- Data.validate_object(decoded) do
          {:ok, decoded}
        else
          {:error, validation_error} ->
            {:error, ensure_json_path(validation_error, path ++ [field])}
        end

      :error ->
        required_field(path ++ [field], field)
    end
  end

  defp diagnose_data(value, _registry, depth, path)
       when is_nil(value) or is_boolean(value) or is_number(value) do
    with :ok <- ensure_depth(depth, path), do: {:ok, value}
  end

  defp diagnose_data(value, _registry, depth, path) when is_binary(value) do
    with :ok <- ensure_depth(depth, path),
         :ok <- valid_utf8(value, path) do
      {:ok, value}
    end
  end

  defp diagnose_data(%{"$type" => "atom"} = record, registry, depth, path) do
    initial =
      unknown_field_errors(record, ["$type", "id"], path) ++
        result_errors(ensure_depth(depth, path)) ++
        result_errors(exact_value(record, "$type", "atom", path))

    case collect_values(
           [value: fn -> resolve_field(record, "id", :atom, registry, path) end],
           initial
         ) do
      {:ok, %{value: atom}} -> {:ok, atom}
      {:error, errors} -> {:error, errors}
    end
  end

  defp diagnose_data(%{"$type" => "mfa"} = record, registry, depth, path) do
    initial =
      unknown_field_errors(record, ["$type", "module", "function", "arguments"], path) ++
        result_errors(ensure_depth(depth, path)) ++
        result_errors(exact_value(record, "$type", "mfa", path))

    fields = [
      module: fn -> resolve_field(record, "module", :atom, registry, path) end,
      function: fn -> resolve_field(record, "function", :atom, registry, path) end,
      arguments: fn ->
        case Map.fetch(record, "arguments") do
          {:ok, values} -> diagnose_data_list(values, registry, depth + 1, path ++ ["arguments"])
          :error -> required_field(path ++ ["arguments"], "arguments")
        end
      end
    ]

    case collect_values(fields, initial) do
      {:ok, attrs} ->
        value = {attrs.module, attrs.function, attrs.arguments}

        case Data.validate(value) do
          :ok -> {:ok, value}
          {:error, validation_error} -> {:error, ensure_json_path(validation_error, path)}
        end

      {:error, errors} ->
        {:error, errors}
    end
  end

  defp diagnose_data(%{"$type" => "map"} = record, registry, depth, path) do
    diagnose_map(record, registry, depth, path)
  end

  defp diagnose_data(value, registry, depth, path) when is_list(value) do
    diagnose_data_list(value, registry, depth, path)
  end

  defp diagnose_data(_value, _registry, _depth, path) do
    {:error, error("stored Agent data has an invalid tagged value", %{path: path})}
  end

  defp diagnose_data_list(values, registry, depth, path) when is_list(values) do
    with :ok <- ensure_depth(depth, path),
         :ok <- ensure_collection_size(values, path) do
      values
      |> Enum.with_index()
      |> collect_sequence(fn {value, index} ->
        diagnose_data(value, registry, depth + 1, path ++ [index])
      end)
    end
  end

  defp diagnose_data_list(_value, _registry, _depth, path) do
    {:error, error("stored Agent data must be a list", %{path: path})}
  end

  defp diagnose_map(record, registry, depth, path) do
    initial =
      unknown_field_errors(record, ["$type", "entries"], path) ++
        result_errors(ensure_depth(depth, path)) ++
        result_errors(exact_value(record, "$type", "map", path))

    entries_result =
      case Map.fetch(record, "entries") do
        {:ok, values} when is_list(values) ->
          diagnose_map_entry_list(values, registry, depth, path)

        {:ok, _value} ->
          {:error, error("stored Agent map entries must be a list", %{path: path ++ ["entries"]})}

        :error ->
          required_field(path ++ ["entries"], "entries")
      end

    case collect_values([entries: fn -> entries_result end], initial) do
      {:ok, %{entries: entries}} -> diagnose_map_entries(entries, path)
      {:error, errors} -> {:error, errors}
    end
  end

  defp diagnose_map_entry_list(values, registry, depth, path) do
    entries_path = path ++ ["entries"]

    with :ok <- ensure_collection_size(values, entries_path) do
      values
      |> Enum.with_index()
      |> collect_sequence(fn {value, index} ->
        diagnose_map_entry(value, registry, depth, entries_path ++ [index], index)
      end)
    end
  end

  defp diagnose_map_entry(%{} = record, registry, depth, path, index)
       when not is_struct(record) do
    fields = [
      key: fn -> diagnose_map_entry_key(record, registry, depth, path) end,
      value: fn -> diagnose_map_entry_value(record, registry, depth, path) end
    ]

    errors = unknown_field_errors(record, ["key", "value"], path)

    case collect_values(fields, errors) do
      {:ok, attrs} -> {:ok, Map.put(attrs, :index, index)}
      {:error, nested} -> {:error, nested}
    end
  end

  defp diagnose_map_entry(_value, _registry, _depth, path, _index) do
    {:error, error("stored Agent map entry must be a map", %{path: path})}
  end

  defp diagnose_map_entry_key(record, registry, depth, path) do
    case Map.fetch(record, "key") do
      {:ok, value} ->
        with {:ok, key} <- diagnose_data(value, registry, depth + 1, path ++ ["key"]),
             :ok <- Data.validate_key(key) do
          {:ok, key}
        else
          {:error, validation_error} ->
            {:error, ensure_json_path(validation_error, path ++ ["key"])}
        end

      :error ->
        required_field(path ++ ["key"], "key")
    end
  end

  defp diagnose_map_entry_value(record, registry, depth, path) do
    case Map.fetch(record, "value") do
      {:ok, value} -> diagnose_data(value, registry, depth + 1, path ++ ["value"])
      :error -> required_field(path ++ ["value"], "value")
    end
  end

  defp diagnose_map_entries(entries, path) do
    {map, errors} =
      Enum.reduce(entries, {%{}, []}, fn %{index: index, key: key, value: value}, {map, errors} ->
        if Map.has_key?(map, key) do
          duplicate =
            error("stored Agent map contains a duplicate key", %{
              path: path ++ ["entries", index, "key"]
            })

          {map, [duplicate | errors]}
        else
          {Map.put(map, key, value), errors}
        end
      end)

    if errors == [], do: {:ok, map}, else: {:error, Enum.reverse(errors)}
  end

  defp encode_plugin_defaults(%PluginDefaults{} = defaults, registry) do
    with {:ok, overrides} <- encode_plugin_default_overrides(defaults.overrides, registry) do
      {:ok, %{"mode" => Atom.to_string(defaults.mode), "overrides" => overrides}}
    end
  end

  defp encode_plugin_default_overrides(overrides, registry) do
    overrides
    |> Enum.sort_by(fn {key, _value} -> :erlang.term_to_binary(key, [:deterministic]) end)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {{state_key, value}, index}, {:ok, encoded} ->
      result =
        with {:ok, state_key} <- Registry.identifier(registry, :atom, state_key),
             {:ok, plugin} <- encode_plugin_default_value(value, registry) do
          {:ok, %{"state_key" => state_key, "plugin" => plugin}}
        end

      case result do
        {:ok, record} ->
          {:cont, {:ok, [record | encoded]}}

        {:error, validation_error} ->
          {:halt, {:error, prefix(validation_error, ["plugin_defaults", "overrides", index])}}
      end
    end)
    |> reverse_ok()
  end

  defp encode_plugin_default_value(:disabled, _registry), do: {:ok, nil}

  defp encode_plugin_default_value(%Plugin{} = plugin, registry),
    do: encode_plugin(plugin, registry)

  defp encode_plugin(%Plugin{} = plugin, registry) do
    with {:ok, module} <- Registry.identifier(registry, :plugin, plugin.module),
         {:ok, as} <- encode_optional_identifier(registry, :atom, plugin.as),
         {:ok, config} <- encode_data(plugin.config, registry, 0),
         {:ok, metadata} <- encode_data(plugin.metadata, registry, 0) do
      {:ok,
       %{
         "module" => module,
         "as" => as,
         "config" => config,
         "metadata" => metadata
       }}
    end
  end

  defp encode_route(%Route{} = route, registry) do
    with {:ok, action, params} <- encode_route_target(route.target),
         {:ok, action} <- Registry.identifier(registry, :action, action),
         {:ok, params} <- encode_optional_data(params, registry),
         {:ok, match} <- encode_optional_identifier(registry, :route_match, route.match) do
      {:ok,
       %{
         "path" => route.path,
         "action" => action,
         "params" => params,
         "match" => match,
         "priority" => route.priority
       }}
    end
  end

  defp encode_route_target({action, params}) when is_atom(action) and is_map(params),
    do: {:ok, action, params}

  defp encode_route_target(action) when is_atom(action), do: {:ok, action, nil}

  defp encode_route_target(value) do
    {:error,
     error("Agent route target must be an Action module with optional static params", %{
       value: value
     })}
  end

  defp encode_schedule(%Schedule{} = schedule, registry) do
    with {:ok, data} <- encode_data(schedule.data, registry, 0),
         {:ok, metadata} <- encode_data(schedule.metadata, registry, 0) do
      {:ok,
       %{
         "name" => schedule.name,
         "cron_expression" => schedule.cron_expression,
         "signal_type" => schedule.signal_type,
         "timezone" => schedule.timezone,
         "data" => data,
         "metadata" => metadata
       }}
    end
  end

  defp encode_extension(%ExtensionDeclaration{} = extension, registry) do
    with {:ok, module} <- Registry.identifier(registry, :extension, extension.module),
         {:ok, data} <- encode_extension_data(extension, registry),
         {:ok, metadata} <- encode_data(extension.metadata, registry, 0) do
      {:ok, %{"module" => module, "data" => data, "metadata" => metadata}}
    end
  end

  defp encode_extension_data(extension, registry) do
    if function_exported?(extension.module, :encode, 2) do
      extension.module
      |> invoke_extension_codec(:encode, [extension.data, registry])
      |> extension_encode_result(extension.module)
    else
      encode_data(extension.data, registry, 0)
    end
  end

  defp extension_encode_result({:ok, document_data}, _module) do
    with :ok <- validate_extension_document_data(document_data), do: {:ok, document_data}
  end

  defp extension_encode_result({:error, %_{} = validation_error}, _module)
       when is_exception(validation_error),
       do: {:error, validation_error}

  defp extension_encode_result({:error, reason}, module) do
    {:error, error("Agent extension encode failed", %{extension: module, reason: reason})}
  end

  defp extension_encode_result(value, module) do
    {:error,
     error("Agent extension encode returned an invalid value", %{
       extension: module,
       value: value
     })}
  end

  defp validate_extension_document_data(value)
       when is_nil(value) or is_boolean(value) or is_number(value),
       do: :ok

  defp validate_extension_document_data(value) when is_binary(value), do: valid_utf8(value, [])

  defp validate_extension_document_data(value) when is_list(value) do
    if List.improper?(value) do
      {:error, error("Agent extension document data must contain proper lists")}
    else
      Enum.reduce_while(value, :ok, fn item, :ok ->
        case validate_extension_document_data(item) do
          :ok -> {:cont, :ok}
          {:error, validation_error} -> {:halt, {:error, validation_error}}
        end
      end)
    end
  end

  defp validate_extension_document_data(value) when is_map(value) and not is_struct(value) do
    Enum.reduce_while(value, :ok, fn
      {key, item}, :ok when is_binary(key) ->
        with :ok <- valid_utf8(key, []),
             :ok <- validate_extension_document_data(item) do
          {:cont, :ok}
        else
          {:error, validation_error} -> {:halt, {:error, validation_error}}
        end

      {_key, _item}, :ok ->
        {:halt, {:error, error("Agent extension document Map keys must be strings")}}
    end)
  end

  defp validate_extension_document_data(_value),
    do: {:error, error("Agent extension encode must return JSON-compatible data")}

  defp invoke_extension_codec(module, callback, arguments) do
    apply(module, callback, arguments)
  rescue
    exception ->
      {:error,
       error("Agent extension #{callback} raised", %{
         extension: module,
         exception: exception
       })}
  catch
    kind, reason ->
      {:error,
       error("Agent extension #{callback} failed", %{
         extension: module,
         kind: kind,
         reason: reason
       })}
  end

  defp encode_sequence(values, field, registry, encoder) do
    with :ok <- collection_size(values) do
      encode_sequence_values(values, field, registry, encoder)
    end
  end

  defp encode_sequence_values(values, field, registry, encoder) do
    values
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {value, index}, {:ok, encoded} ->
      case encoder.(value, registry) do
        {:ok, record} ->
          {:cont, {:ok, [record | encoded]}}

        {:error, validation_error} ->
          {:halt, {:error, prefix(validation_error, [field, index])}}
      end
    end)
    |> reverse_ok()
  end

  defp encode_optional_identifier(_registry, _kind, nil), do: {:ok, nil}

  defp encode_optional_identifier(registry, kind, value),
    do: Registry.identifier(registry, kind, value)

  defp encode_optional_data(nil, _registry), do: {:ok, nil}
  defp encode_optional_data(value, registry), do: encode_data(value, registry, 0)

  defp encode_data(value, _registry, depth)
       when is_nil(value) or is_boolean(value) or is_number(value) do
    with :ok <- depth(depth), do: {:ok, value}
  end

  defp encode_data(value, _registry, depth) when is_binary(value) do
    with :ok <- depth(depth),
         :ok <- valid_utf8(value, []) do
      {:ok, value}
    end
  end

  defp encode_data({module, function, arguments}, registry, depth)
       when is_atom(module) and is_atom(function) and is_list(arguments) do
    with :ok <- depth(depth),
         {:ok, module} <- Registry.identifier(registry, :atom, module),
         {:ok, function} <- Registry.identifier(registry, :atom, function),
         {:ok, arguments} <- encode_list(arguments, registry, depth + 1) do
      {:ok,
       %{
         "$type" => "mfa",
         "module" => module,
         "function" => function,
         "arguments" => arguments
       }}
    end
  end

  defp encode_data(value, registry, depth) when is_atom(value) do
    with :ok <- depth(depth),
         {:ok, identifier} <- Registry.identifier(registry, :atom, value) do
      {:ok, %{"$type" => "atom", "id" => identifier}}
    end
  end

  defp encode_data(value, registry, depth) when is_list(value) do
    encode_list(value, registry, depth)
  end

  defp encode_data(value, registry, depth) when is_map(value) and not is_struct(value) do
    encode_map(value, registry, depth)
  end

  defp encode_data(value, _registry, _depth) do
    {:error, error("Agent data contains an unsupported value", %{value: value})}
  end

  defp encode_list(values, registry, depth) do
    with :ok <- depth(depth),
         false <- List.improper?(values),
         :ok <- collection_size(values) do
      encode_list_values(values, registry, depth)
    else
      true -> {:error, error("Agent data must contain proper lists")}
      {:error, validation_error} -> {:error, validation_error}
    end
  end

  defp encode_list_values(values, registry, depth) do
    values
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {value, index}, {:ok, encoded} ->
      case encode_data(value, registry, depth + 1) do
        {:ok, item} ->
          {:cont, {:ok, [item | encoded]}}

        {:error, validation_error} ->
          {:halt, {:error, prefix(validation_error, [index])}}
      end
    end)
    |> reverse_ok()
  end

  defp encode_map(map, registry, depth) do
    with :ok <- depth(depth),
         :ok <- map_collection_size(map),
         {:ok, entries} <- encode_map_entries(map, registry, depth) do
      entries = Enum.sort_by(entries, fn %{"key" => key} -> :erlang.term_to_binary(key) end)
      {:ok, %{"$type" => "map", "entries" => entries}}
    end
  end

  defp encode_map_entries(map, registry, depth) do
    Enum.reduce_while(map, {:ok, []}, fn {key, value}, {:ok, encoded} ->
      result =
        with :ok <- Data.validate_key(key),
             {:ok, key} <- encode_data(key, registry, depth + 1),
             {:ok, value} <- encode_data(value, registry, depth + 1) do
          {:ok, %{"key" => key, "value" => value}}
        end

      case result do
        {:ok, entry} -> {:cont, {:ok, [entry | encoded]}}
        {:error, validation_error} -> {:halt, {:error, validation_error}}
      end
    end)
  end

  defp resolve_optional_field(record, field, kind, registry, path) do
    case Map.fetch(record, field) do
      {:ok, nil} -> {:ok, nil}
      {:ok, _value} -> resolve_field(record, field, kind, registry, path)
      :error -> required_field(path ++ [field], field)
    end
  end

  defp resolve_field(record, field, kind, registry, path) do
    case Map.fetch(record, field) do
      {:ok, identifier} when is_binary(identifier) ->
        case Registry.resolve(registry, identifier, kind) do
          {:ok, value} ->
            {:ok, value}

          {:error, validation_error} ->
            {:error, ensure_json_path(validation_error, path ++ [field])}
        end

      {:ok, _value} ->
        {:error,
         error("stored Agent Registry identifier must be a string", %{
           path: path ++ [field]
         })}

      :error ->
        required_field(path ++ [field], field)
    end
  end

  defp exact_value(record, field, expected, path) do
    case Map.fetch(record, field) do
      {:ok, ^expected} ->
        :ok

      {:ok, actual} ->
        {:error,
         error("stored Agent field has an unsupported value", %{
           path: path ++ [field],
           expected: expected,
           actual: actual
         })}

      :error ->
        {:error, error("stored Agent field is required", %{path: path ++ [field], field: field})}
    end
  end

  defp string_field(record, field, path) do
    case Map.fetch(record, field) do
      {:ok, value} when is_binary(value) ->
        case valid_utf8(value, path ++ [field]) do
          :ok -> {:ok, value}
          {:error, validation_error} -> {:error, validation_error}
        end

      {:ok, _value} ->
        {:error, error("stored Agent field must be a string", %{path: path ++ [field]})}

      :error ->
        required_field(path ++ [field], field)
    end
  end

  defp optional_string_field(record, field, path) do
    case Map.fetch(record, field) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, value} when is_binary(value) ->
        string_field(record, field, path)

      {:ok, _value} ->
        {:error, error("stored Agent field must be a string or null", %{path: path ++ [field]})}

      :error ->
        required_field(path ++ [field], field)
    end
  end

  defp valid_utf8(value, path) do
    if String.valid?(value) do
      :ok
    else
      {:error, error("stored Agent strings must be valid UTF-8", %{path: path})}
    end
  end

  defp collect_values(fields, initial_errors \\ []) do
    {values, errors} =
      Enum.reduce(fields, {%{}, Enum.reverse(initial_errors)}, fn {key, validator},
                                                                  {values, errors} ->
        case validator.() do
          {:ok, value} -> {Map.put(values, key, value), errors}
          {:error, nested} when is_list(nested) -> {values, Enum.reverse(nested, errors)}
          {:error, validation_error} -> {values, [validation_error | errors]}
        end
      end)

    if errors == [], do: {:ok, values}, else: {:error, Enum.reverse(errors)}
  end

  defp collect_sequence(values, validator) do
    {decoded, errors} =
      Enum.reduce(values, {[], []}, fn value, {decoded, errors} ->
        case validator.(value) do
          {:ok, item} -> {[item | decoded], errors}
          {:error, nested} when is_list(nested) -> {decoded, Enum.reverse(nested, errors)}
          {:error, validation_error} -> {decoded, [validation_error | errors]}
        end
      end)

    if errors == [],
      do: {:ok, Enum.reverse(decoded)},
      else: {:error, Enum.reverse(errors)}
  end

  defp unknown_field_errors(record, allowed, path) do
    record
    |> Map.keys()
    |> Enum.reject(&(&1 in allowed))
    |> Enum.sort_by(&json_path_segment/1)
    |> Enum.map(fn field ->
      error("stored Agent contains an unknown field", %{
        path: path ++ [json_path_segment(field)],
        field: field
      })
    end)
  end

  defp result_errors(:ok), do: []
  defp result_errors({:error, validation_error}), do: [validation_error]

  defp required_field(path, field) do
    {:error, error("stored Agent field is required", %{path: path, field: field})}
  end

  defp diagnose_constructor({:ok, value}, _path), do: {:ok, value}

  defp diagnose_constructor({:error, validation_error}, path) do
    {:error, ensure_json_path(validation_error, path)}
  end

  defp ensure_json_path(%{details: details} = validation_error, base_path)
       when is_map(details) do
    local_path = details |> Map.get(:path, []) |> Enum.map(&json_path_segment/1)

    path =
      if path_starts_with?(local_path, base_path),
        do: local_path,
        else: base_path ++ local_path

    %{validation_error | details: Map.put(details, :path, path)}
  end

  defp ensure_json_path(validation_error, _base_path), do: validation_error

  defp path_starts_with?(path, prefix), do: Enum.take(path, length(prefix)) == prefix

  defp json_path_segment(segment) when is_binary(segment) or is_integer(segment), do: segment
  defp json_path_segment(segment) when is_atom(segment), do: Atom.to_string(segment)
  defp json_path_segment(segment), do: inspect(segment)

  defp diagnostic_failure(errors), do: {:error, Error.to_class(errors)}

  defp ensure_depth(value, path) do
    case depth(value) do
      :ok -> :ok
      {:error, validation_error} -> {:error, ensure_json_path(validation_error, path)}
    end
  end

  defp ensure_collection_size(values, path) do
    case collection_size(values) do
      :ok -> :ok
      {:error, validation_error} -> {:error, ensure_json_path(validation_error, path)}
    end
  end

  defp depth(value) when value <= @maximum_depth, do: :ok

  defp depth(_value) do
    {:error, error("stored Agent exceeds its nesting limit", %{maximum_depth: @maximum_depth})}
  end

  defp collection_size(values) when length(values) <= @maximum_collection_size, do: :ok

  defp collection_size(_values) do
    {:error,
     error("stored Agent collection exceeds its size limit", %{
       maximum_size: @maximum_collection_size
     })}
  end

  defp map_collection_size(value) when map_size(value) <= @maximum_collection_size, do: :ok

  defp map_collection_size(_value) do
    {:error,
     error("stored Agent collection exceeds its size limit", %{
       maximum_size: @maximum_collection_size
     })}
  end

  defp validate_document_limits(document) do
    case count_document_nodes(document, 0, @maximum_document_nodes) do
      {:ok, _remaining} -> :ok
      {:error, validation_error} -> {:error, validation_error}
    end
  end

  defp count_document_nodes(_value, _depth, remaining) when remaining <= 0 do
    {:error,
     error("stored Agent exceeds its total node limit", %{
       maximum_nodes: @maximum_document_nodes
     })}
  end

  defp count_document_nodes(value, depth, remaining) when is_binary(value) do
    with :ok <- depth(depth),
         :ok <- valid_utf8(value, []) do
      {:ok, remaining - 1}
    end
  end

  defp count_document_nodes(value, depth, remaining) when is_list(value) do
    with :ok <- depth(depth),
         false <- List.improper?(value),
         :ok <- collection_size(value) do
      count_list_nodes(value, depth, remaining - 1)
    else
      true -> {:error, error("stored Agent data must contain proper lists")}
      {:error, validation_error} -> {:error, validation_error}
    end
  end

  defp count_document_nodes(value, depth, remaining)
       when is_map(value) and not is_struct(value) do
    with :ok <- depth(depth),
         :ok <- map_collection_size(value) do
      count_map_nodes(value, depth, remaining - 1)
    end
  end

  defp count_document_nodes(_value, depth, remaining) do
    with :ok <- depth(depth), do: {:ok, remaining - 1}
  end

  defp count_list_nodes(values, depth, remaining) do
    Enum.reduce_while(values, {:ok, remaining}, fn item, {:ok, remaining} ->
      case count_document_nodes(item, depth + 1, remaining) do
        {:ok, next_remaining} -> {:cont, {:ok, next_remaining}}
        {:error, validation_error} -> {:halt, {:error, validation_error}}
      end
    end)
  end

  defp count_map_nodes(value, depth, remaining) do
    Enum.reduce_while(value, {:ok, remaining}, fn {key, item}, {:ok, remaining} ->
      with {:ok, remaining} <- count_document_nodes(key, depth + 1, remaining),
           {:ok, remaining} <- count_document_nodes(item, depth + 1, remaining) do
        {:cont, {:ok, remaining}}
      else
        {:error, validation_error} -> {:halt, {:error, validation_error}}
      end
    end)
  end

  defp error(message, details \\ %{}),
    do: Error.validation_error(message, details: details)

  defp prefix(%{details: details} = validation_error, path) when is_map(details) do
    %{validation_error | details: Map.put(details, :path, path ++ Map.get(details, :path, []))}
  end

  defp prefix(validation_error, _path), do: validation_error

  defp reverse_ok({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_ok(error), do: error
end
