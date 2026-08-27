defmodule Jido.Agent.Registry.Deriver do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Agent.Extension.Declaration, as: ExtensionDeclaration
  alias Jido.Agent.Plugin
  alias Jido.Agent.PluginDefaults
  alias Jido.Agent.Schedule
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
  @spec entries(Agent.t()) :: %{String.t() => Jido.Agent.Registry.write_entry()}
  def entries(%Agent{} = agent) do
    values =
      empty_values()
      |> add(:schema, agent.state_schema)
      |> collect_plugin_defaults(agent.plugin_defaults)
      |> collect_plugins(agent.plugins)
      |> collect_routes(agent.routes)
      |> collect_schedules(agent.schedules)
      |> collect_extensions(agent.extensions)
      |> collect_data(agent.metadata)

    @kinds
    |> Enum.flat_map(fn kind ->
      values
      |> sorted_values(kind)
      |> Enum.with_index(1)
      |> Enum.map(fn {value, index} ->
        identifier = "#{Map.fetch!(@namespaces, kind)}/generated-#{index}"
        {identifier, {kind, value}}
      end)
    end)
    |> Map.new()
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
    Enum.reduce(extensions, values, &collect_extension(&2, &1))
  end

  defp collect_extension(values, %ExtensionDeclaration{} = extension) do
    values
    |> add(:extension, extension.module)
    |> collect_data(extension.data)
    |> collect_data(extension.metadata)
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
end
