defmodule Jido.Agent.Codec.Deriver do
  @moduledoc false
  alias Jido.Agent.Codec
  alias Jido.Agent.Codec.Registry

  def agent(agent) do
    entries = [{:agent, agent.module}, {:schema, agent.schema}] ++ data(agent.metadata)
    entries = entries ++ Enum.flat_map(agent.plugins, &plugin_entries/1)

    entries =
      entries ++
        Enum.flat_map(agent.routes, fn route ->
          {target, defaults} = Codec.target(route.target)
          {:ok, executable} = Jido.Executable.resolve(target)
          match = if route.match == nil, do: [], else: [{:route_match, route.match}]
          [{executable.kind, target} | data(defaults)] ++ match
        end)

    build(entries)
  end

  def plugin(plugin), do: build(plugin_entries(plugin))

  defp plugin_entries({module, options}), do: [{:plugin, module} | data(options)]

  defp data(value)
       when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value), do: []

  defp data(value) when is_atom(value), do: [{:atom, value}]
  defp data(value) when is_struct(value), do: [{:value, value}]

  defp data(value) when is_map(value),
    do: Enum.flat_map(Enum.sort(value), fn {key, value} -> data(key) ++ data(value) end)

  defp data(value) when is_tuple(value), do: data(Tuple.to_list(value))
  defp data([]), do: []
  defp data([head | tail]), do: data(head) ++ data(tail)
  defp data(_value), do: []

  defp build(entries) do
    entries
    |> Enum.uniq()
    |> Enum.with_index()
    |> Map.new(fn {{kind, _} = entry, index} ->
      {"#{kind}/#{index}", entry}
    end)
    |> Registry.new()
  end
end
