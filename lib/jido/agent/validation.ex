defmodule Jido.Agent.Validation do
  @moduledoc false

  alias Jido.Agent.{Data, Extension, Plugin, PluginDefaults, Schedule}
  alias Jido.Error
  alias Jido.Signal.Router
  alias Jido.Signal.Router.Route

  @definition_keys [
    :id,
    :state,
    :agent_module,
    :name,
    :description,
    :state_schema,
    :plugin_defaults,
    :plugins,
    :routes,
    :schedules,
    :extensions,
    :metadata
  ]

  @doc false
  @spec new(map() | keyword()) :: {:ok, map()} | {:error, Exception.t()}
  def new(attrs) do
    with {:ok, attrs} <- validate_attrs(attrs),
         :ok <- definition_lifecycle(attrs) do
      {:ok, attrs}
    end
  end

  @doc false
  @spec validate(map() | keyword()) :: {:ok, map()} | {:error, Exception.t()}
  def validate(attrs) do
    with {:ok, attrs} <- validate_attrs(attrs),
         :ok <- lifecycle(attrs) do
      {:ok, attrs}
    end
  end

  @doc false
  @spec invalid_subject(term()) :: {:error, Exception.t()}
  def invalid_subject(value),
    do: {:error, error("expected a Jido.Agent value", %{value: value})}

  defp validate_attrs(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs),
      do: attrs |> Map.new() |> validate_attrs(),
      else: {:error, error("agent configuration must be a map")}
  end

  defp validate_attrs(%{} = attrs) do
    with :ok <- known_keys(attrs),
         {:ok, name} <- name(Map.get(attrs, :name)),
         {:ok, description} <- description(Map.get(attrs, :description)),
         {:ok, state_schema} <- state_schema(Map.get(attrs, :state_schema, [])),
         {:ok, plugin_defaults} <-
           plugin_defaults(Map.get(attrs, :plugin_defaults, %PluginDefaults{})),
         {:ok, plugins} <- plugins(Map.get(attrs, :plugins, [])),
         {:ok, routes} <- routes(Map.get(attrs, :routes, [])),
         {:ok, schedules} <- schedules(Map.get(attrs, :schedules, [])),
         {:ok, extensions} <- extensions(Map.get(attrs, :extensions, [])),
         {:ok, metadata} <- metadata(Map.get(attrs, :metadata, %{})),
         {:ok, id} <- id(Map.get(attrs, :id)),
         {:ok, state} <- state(Map.get(attrs, :state)),
         {:ok, agent_module} <- agent_module(Map.get(attrs, :agent_module)) do
      {:ok,
       %{
         id: id,
         state: state,
         agent_module: agent_module,
         name: name,
         description: description,
         state_schema: state_schema,
         plugin_defaults: plugin_defaults,
         plugins: plugins,
         routes: routes,
         schedules: schedules,
         extensions: extensions,
         metadata: metadata
       }}
    end
  end

  defp validate_attrs(_attrs), do: {:error, error("agent configuration must be a map")}

  defp known_keys(attrs) do
    case Enum.find(Map.keys(attrs), &(&1 not in @definition_keys)) do
      nil -> :ok
      key -> {:error, error("unknown Agent configuration key: #{inspect(key)}", %{key: key})}
    end
  end

  defp name(value) do
    case Jido.Util.validate_name(value) do
      {:ok, name} -> {:ok, name}
      {:error, validation_error} -> {:error, prefix(validation_error, [:name])}
    end
  end

  defp description(nil), do: {:ok, nil}

  defp description(value) when is_binary(value) do
    if String.valid?(value),
      do: {:ok, value},
      else: {:error, error("agent description must be valid UTF-8", %{path: [:description]})}
  end

  defp description(_value),
    do: {:error, error("agent description must be a string", %{path: [:description]})}

  defp state_schema(nil), do: {:ok, []}

  defp state_schema(value) do
    with :ok <- static_schema(value),
         :ok <- valid_state_schema(value) do
      {:ok, value}
    end
  end

  defp static_schema(value) do
    case Jido.Action.validate_static_data(value) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         error("state_schema must be static module data; #{reason}", %{path: [:state_schema]})}
    end
  end

  defp valid_state_schema(value) do
    case Jido.Agent.State.validate_schema(value, []) do
      :ok -> :ok
      {:error, reason} -> {:error, error("state_schema #{reason}", %{path: [:state_schema]})}
    end
  end

  defp plugin_defaults(value) do
    case PluginDefaults.new(value) do
      {:ok, defaults} -> {:ok, defaults}
      {:error, validation_error} -> {:error, prefix(validation_error, [:plugin_defaults])}
    end
  end

  defp plugins(value), do: canonical_list(value, :plugins, &Plugin.new/1)

  defp routes(value) when is_list(value) do
    if List.improper?(value) do
      {:error, error("agent routes must be a proper list", %{path: [:routes]})}
    else
      route_specs = Enum.map(value, &normalize_agent_route_spec/1)

      case Router.normalize(route_specs) do
        {:ok, routes} ->
          validate_routes(routes)

        {:error, reason} ->
          {:error, error("invalid Agent routes", %{path: [:routes], reason: reason})}
      end
    end
  end

  defp routes(_value), do: {:error, error("agent routes must be a list", %{path: [:routes]})}

  defp normalize_agent_route_spec({path, target, params})
       when is_binary(path) and is_atom(target) and is_map(params),
       do: {path, {target, params}}

  defp normalize_agent_route_spec({path, target, params, priority})
       when is_binary(path) and is_atom(target) and is_map(params) and is_integer(priority),
       do: {path, {target, params}, priority}

  defp normalize_agent_route_spec({path, match, target, params})
       when is_binary(path) and is_function(match, 1) and is_atom(target) and is_map(params),
       do: {path, match, {target, params}}

  defp normalize_agent_route_spec({path, match, target, params, priority})
       when is_binary(path) and is_function(match, 1) and is_atom(target) and is_map(params) and
              is_integer(priority),
       do: {path, match, {target, params}, priority}

  defp normalize_agent_route_spec(route_spec), do: route_spec

  defp validate_routes(routes) do
    routes
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {%Route{} = route, index}, {:ok, acc} ->
      with :ok <- route_match(route.match, index),
           :ok <- route_target_data(route.target, index) do
        {:cont, {:ok, [route | acc]}}
      else
        {:error, validation_error} -> {:halt, {:error, validation_error}}
      end
    end)
    |> reverse_ok()
  end

  defp route_match(match, index) do
    if stable_external_unary_capture?(match) do
      :ok
    else
      {:error,
       error("agent route matches must be stable external unary function captures", %{
         path: [:routes, index, :match]
       })}
    end
  end

  defp route_target_data({module, params}, index) when is_atom(module) and is_map(params) do
    case Data.validate_object(params) do
      :ok ->
        :ok

      {:error, validation_error} ->
        {:error, prefix(validation_error, [:routes, index, :target, 1])}
    end
  end

  defp route_target_data(_target, _index), do: :ok

  defp stable_external_unary_capture?(nil), do: true

  defp stable_external_unary_capture?(function) when is_function(function, 1) do
    :erlang.fun_info(function, :type) == {:type, :external} and
      :erlang.fun_info(function, :env) == {:env, []}
  end

  defp stable_external_unary_capture?(_value), do: false

  defp schedules(value) do
    with {:ok, schedules} <- canonical_list(value, :schedules, &Schedule.new/1),
         :ok <- unique(schedules, & &1.name, :schedules, "schedule name") do
      {:ok, schedules}
    end
  end

  defp extensions(value) do
    with {:ok, extensions} <-
           canonical_list(value, :extensions, &Extension.Declaration.new/1),
         :ok <- unique(extensions, & &1.module, :extensions, "extension module") do
      {:ok, extensions}
    end
  end

  defp canonical_list(value, field, constructor) when is_list(value) do
    if List.improper?(value) do
      {:error, error("agent #{field} must be a proper list", %{path: [field]})}
    else
      value
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, acc} ->
        case constructor.(item) do
          {:ok, canonical} ->
            {:cont, {:ok, [canonical | acc]}}

          {:error, validation_error} ->
            {:halt, {:error, prefix(validation_error, [field, index])}}
        end
      end)
      |> reverse_ok()
    end
  end

  defp canonical_list(_value, field, _constructor),
    do: {:error, error("agent #{field} must be a list", %{path: [field]})}

  defp unique(values, key_function, field, label) do
    values
    |> Enum.map(key_function)
    |> then(fn keys -> keys -- Enum.uniq(keys) end)
    |> case do
      [] ->
        :ok

      [duplicate | _] ->
        {:error, error("duplicate Agent #{label}", %{path: [field], value: duplicate})}
    end
  end

  defp metadata(value) do
    case Data.validate_object(value) do
      :ok -> {:ok, value}
      {:error, validation_error} -> {:error, prefix(validation_error, [:metadata])}
    end
  end

  defp id(nil), do: {:ok, nil}

  defp id(value) when is_binary(value) do
    if String.valid?(value),
      do: {:ok, value},
      else: {:error, error("agent instance ID must be valid UTF-8", %{path: [:id]})}
  end

  defp id(_value), do: {:error, error("agent instance ID must be a string", %{path: [:id]})}

  defp state(nil), do: {:ok, nil}
  defp state(value) when is_map(value), do: {:ok, value}
  defp state(_value), do: {:error, error("agent instance state must be a map", %{path: [:state]})}

  defp agent_module(nil), do: {:ok, nil}

  defp agent_module(value) when is_atom(value) and value not in [true, false], do: {:ok, value}

  defp agent_module(_value),
    do: {:error, error("agent module binding must be a module atom", %{path: [:agent_module]})}

  defp definition_lifecycle(%{id: nil, state: nil, agent_module: nil}), do: :ok

  defp definition_lifecycle(_attrs) do
    {:error,
     error("Jido.Agent.new/1 builds definitions and does not accept runtime fields", %{
       path: [:id, :state, :agent_module]
     })}
  end

  defp lifecycle(%{id: nil, state: nil, agent_module: nil}), do: :ok

  defp lifecycle(%{id: id, state: state})
       when is_binary(id) and id != "" and is_map(state),
       do: :ok

  defp lifecycle(%{id: nil, state: state}) when is_map(state),
    do: invalid_lifecycle([:id])

  defp lifecycle(%{id: id, state: nil}) when is_binary(id) and id != "",
    do: invalid_lifecycle([:state])

  defp lifecycle(%{id: "", state: state}) when is_map(state),
    do: invalid_lifecycle([:id])

  defp lifecycle(%{id: nil, state: nil}),
    do: invalid_lifecycle([:agent_module])

  defp lifecycle(_attrs), do: invalid_lifecycle([:id, :state])

  defp invalid_lifecycle(path) do
    {:error,
     error("agent runtime fields form an invalid lifecycle state", %{
       path: path,
       lifecycle: :half_instance
     })}
  end

  defp reverse_ok({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_ok({:error, _error} = result), do: result

  defp error(message, details \\ %{}),
    do: Error.validation_error(message, details: details)

  defp prefix(%{details: details} = validation_error, path) when is_map(details),
    do: %{
      validation_error
      | details: Map.put(details, :path, path ++ Map.get(details, :path, []))
    }

  defp prefix(validation_error, _path), do: validation_error
end
