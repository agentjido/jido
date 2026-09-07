defmodule Jido.Agent.Codec.Deriver do
  @moduledoc false
  alias Jido.Agent.Authoring
  alias Jido.Agent.Codec.Registry

  def agent(agent) do
    []
    |> add(:agent, agent.module)
    |> add(:schema, agent.schema)
    |> data(agent.metadata)
    |> collect(agent.plugins, &plugin_entries/2)
    |> collect(agent.routes, &route_entries/2)
    |> build()
  end

  def plugin(plugin), do: [] |> plugin_entries(plugin) |> build()

  defp plugin_entries(entries, {module, options}),
    do: entries |> add(:plugin, module) |> data(options)

  defp route_entries(entries, route) do
    {target, defaults} = Authoring.split_target(route.target)
    {:ok, executable} = Jido.Executable.resolve(target)
    entries = entries |> add(executable.kind, target) |> data(defaults)
    if is_nil(route.match), do: entries, else: add(entries, :route_match, route.match)
  end

  defp collect(entries, values, fun), do: Enum.reduce(values, entries, &fun.(&2, &1))

  defp data(entries, value)
       when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value),
       do: entries

  defp data(entries, value) when is_atom(value), do: add(entries, :atom, value)
  defp data(entries, value) when is_struct(value), do: add(entries, :value, value)

  defp data(entries, value) when is_map(value) do
    Enum.reduce(Enum.sort(value), entries, fn {key, value}, entries ->
      entries |> data(key) |> data(value)
    end)
  end

  defp data(entries, value) when is_tuple(value), do: data(entries, Tuple.to_list(value))
  defp data(entries, [head | tail]), do: entries |> data(head) |> data(tail)
  defp data(entries, _value), do: entries

  # As in Flow's Deriver, collect into an accumulator. Keep Agent's existing
  # first-occurrence IDs and exact deduplication; lookup still uses ==.
  defp add(entries, kind, value), do: [{kind, value} | entries]

  defp build(entries) do
    entries
    |> Enum.reverse()
    |> Enum.uniq()
    |> Enum.with_index()
    |> Map.new(fn {{kind, _} = entry, index} ->
      {"#{kind}/#{index}", entry}
    end)
    |> Registry.new()
  end
end
