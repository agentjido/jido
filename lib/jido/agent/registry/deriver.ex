defmodule Jido.Agent.Registry.Deriver do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Agent.Extension.Declaration, as: ExtensionDeclaration
  alias Jido.Agent.Plugin
  alias Jido.Agent.PluginDefaults
  alias Jido.Agent.Schedule
  alias Jido.Error
  alias Jido.Signal.Router.Route

  @kinds [:plugin, :action, :schema, :route_match, :extension, :atom]
  @namespaces %{
    plugin: "plugins",
    action: "actions",
    schema: "schemas",
    route_match: "route-matches",
    extension: "extensions",
    atom: "atoms"
  }

  @doc false
  @spec entries(Agent.t()) ::
          {:ok, %{String.t() => Jido.Agent.Registry.write_entry()}}
          | {:error, Exception.t()}
  def entries(%Agent{} = agent) do
    core_values =
      empty_values()
      |> add(:schema, agent.state_schema)
      |> collect_plugin_defaults(agent.plugin_defaults)
      |> collect_plugins(agent.plugins)
      |> collect_routes(agent.routes)
      |> collect_schedules(agent.schedules)
      |> collect_data(agent.metadata)

    with {:ok, values} <- collect_extensions(core_values, agent.extensions) do
      {:ok, generated_entries(values)}
    end
  end

  defp empty_values, do: Map.new(@kinds, &{&1, MapSet.new()})

  defp add(values, _kind, nil), do: values

  defp add(values, kind, value) do
    Map.update!(values, kind, &MapSet.put(&1, value))
  end

  defp sorted_values(values, kind) do
    values
    |> Map.fetch!(kind)
    |> MapSet.to_list()
    |> Enum.sort_by(&:erlang.term_to_binary(&1, [:deterministic]))
  end

  defp generated_entries(values) do
    core_entries =
      Enum.flat_map(@kinds, fn kind ->
        values
        |> sorted_values(kind)
        |> Enum.with_index(1)
        |> Enum.map(fn {value, index} ->
          identifier = "#{Map.fetch!(@namespaces, kind)}/generated-#{index}"
          {identifier, {kind, value}}
        end)
      end)

    extension_entries =
      values
      |> Map.drop(@kinds)
      |> Enum.flat_map(fn {kind, extension_values} ->
        Enum.map(extension_values, &{kind, &1})
      end)
      |> Enum.sort_by(fn {kind, value} ->
        :erlang.term_to_binary({kind, value}, [:deterministic])
      end)
      |> Enum.with_index(1)
      |> Enum.map(fn {{kind, value}, index} ->
        {"extension-values/generated-#{index}", {kind, value}}
      end)

    Map.new(core_entries ++ extension_entries)
  end

  defp collect_plugin_defaults(values, %PluginDefaults{} = defaults) do
    Enum.reduce(defaults.overrides, values, fn
      {state_key, :disabled}, values ->
        add(values, :atom, state_key)

      {state_key, %Plugin{} = plugin}, values ->
        values
        |> add(:atom, state_key)
        |> collect_plugin(plugin)
    end)
  end

  defp collect_plugins(values, plugins) do
    Enum.reduce(plugins, values, &collect_plugin(&2, &1))
  end

  defp collect_plugin(values, %Plugin{} = plugin) do
    values
    |> add(:plugin, plugin.module)
    |> add(:atom, plugin.as)
    |> collect_data(plugin.config)
    |> collect_data(plugin.metadata)
  end

  defp collect_routes(values, routes) do
    Enum.reduce(routes, values, &collect_route(&2, &1))
  end

  defp collect_route(values, %Route{} = route) do
    values
    |> collect_route_target(route.target)
    |> add(:route_match, route.match)
  end

  defp collect_route_target(values, {action, params}) do
    values
    |> add(:action, action)
    |> collect_data(params)
  end

  defp collect_route_target(values, action), do: add(values, :action, action)

  defp collect_schedules(values, schedules) do
    Enum.reduce(schedules, values, &collect_schedule(&2, &1))
  end

  defp collect_schedule(values, %Schedule{} = schedule) do
    values
    |> collect_data(schedule.signal_type)
    |> collect_data(schedule.data)
    |> collect_data(schedule.metadata)
  end

  defp collect_extensions(values, extensions) do
    Enum.reduce_while(extensions, {:ok, values}, fn extension, {:ok, values} ->
      case collect_extension(values, extension) do
        {:ok, values} -> {:cont, {:ok, values}}
        {:error, validation_error} -> {:halt, {:error, validation_error}}
      end
    end)
  end

  defp collect_extension(values, %ExtensionDeclaration{} = extension) do
    values =
      values
      |> add(:extension, extension.module)
      |> collect_data(extension.metadata)

    if function_exported?(extension.module, :registry_values, 1) do
      with {:ok, entries} <- extension_registry_values(extension),
           {:ok, values} <- add_extension_values(values, extension.module, entries) do
        {:ok, values}
      end
    else
      {:ok, collect_data(values, extension.data)}
    end
  end

  defp extension_registry_values(extension) do
    case extension.module.registry_values(extension.data) do
      entries when is_list(entries) ->
        {:ok, entries}

      value ->
        {:error,
         error("Agent extension Registry collection returned an invalid value", %{
           extension: extension.module,
           value: value
         })}
    end
  rescue
    exception ->
      {:error,
       error("Agent extension Registry collection raised", %{
         extension: extension.module,
         exception: exception
       })}
  catch
    kind, reason ->
      {:error,
       error("Agent extension Registry collection failed", %{
         extension: extension.module,
         kind: kind,
         reason: reason
       })}
  end

  defp add_extension_values(values, extension, entries) do
    Enum.reduce_while(entries, {:ok, values}, fn
      {local_kind, value}, {:ok, values}
      when is_atom(local_kind) and local_kind not in [nil, true, false] ->
        kind = {:extension, extension, local_kind}
        {:cont, {:ok, Map.update(values, kind, MapSet.new([value]), &MapSet.put(&1, value))}}

      entry, {:ok, _values} ->
        {:halt,
         {:error,
          error("Agent extension Registry collection returned an invalid entry", %{
            extension: extension,
            entry: entry
          })}}
    end)
  end

  defp collect_data(values, value)
       when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value),
       do: values

  defp collect_data(values, value) when is_atom(value), do: add(values, :atom, value)

  defp collect_data(values, value) when is_list(value) do
    Enum.reduce(value, values, &collect_data(&2, &1))
  end

  defp collect_data(values, value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.reduce(values, &collect_data(&2, &1))
  end

  defp collect_data(values, value) when is_map(value) do
    value
    |> Map.to_list()
    |> Enum.sort_by(fn {key, _item} -> :erlang.term_to_binary(key, [:deterministic]) end)
    |> Enum.reduce(values, fn {key, item}, values ->
      values
      |> collect_data(key)
      |> collect_data(item)
    end)
  end

  defp collect_data(values, _value), do: values

  defp error(message, details),
    do: Error.validation_error(message, details: details)
end
