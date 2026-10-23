defmodule JidoTest.AgentRegistry do
  @moduledoc false

  alias Jido.Agent
  alias Jido.Authoring
  alias Jido.Authoring.Registry

  @codec Jido.Agent.Codec

  def encode(source, registry),
    do: Authoring.encode(source, registry: registry, codec: @codec)

  def decode(document, registry),
    do: Authoring.decode(document, registry: registry, codec: @codec)

  def encode_json(source, registry),
    do: Authoring.encode_json(source, registry: registry, codec: @codec)

  def decode_json(json, registry),
    do: Authoring.decode_json(json, registry: registry, codec: @codec)

  def for(source) do
    definition = Agent.definition(source)

    definition
    |> references()
    |> Enum.uniq()
    |> Enum.sort_by(fn {kind, value} -> {kind, :erlang.term_to_binary(value)} end)
    |> Enum.with_index(1)
    |> Map.new(fn {{kind, value}, index} ->
      {{"#{kind}/test-#{index}", 1}, {kind, value}}
    end)
    |> Registry.new!()
  end

  defp references(%Agent{} = agent) do
    optional(:agent, agent.module) ++
      [{:schema, agent.schema}] ++
      references(agent.initial_state) ++
      references(agent.metadata) ++
      Enum.flat_map(agent.routes, &route_references/1) ++
      topology_references(agent.topology) ++
      Enum.flat_map(agent.extensions, &extension_references/1)
  end

  defp references(value) when is_atom(value) and value not in [nil, true, false],
    do: [{:atom, value}]

  defp references(value) when is_map(value) and not is_struct(value),
    do: Enum.flat_map(value, fn {key, item} -> references(key) ++ references(item) end)

  defp references(value) when is_list(value), do: Enum.flat_map(value, &references/1)
  defp references(_value), do: []

  defp route_references(route) do
    handler = route.handler

    target =
      case handler do
        %{kind: kind, target: value} when kind in [:action, :flow, :transform] -> [{kind, value}]
        %{kind: :forward, target: %{kind: :agent, name: name}} -> references(name)
        _handler -> []
      end

    target ++ references(route.as) ++ references(route.defaults)
  end

  defp topology_references(%{agents: agents, connections: connections}) do
    Enum.flat_map(agents, fn member ->
      definition =
        case member.definition do
          %Agent{} = agent -> references(agent)
          module when is_atom(module) -> [{:agent, module}]
        end

      definition ++
        references(member.name) ++
        references(member.count) ++
        references(member.initial_state) ++
        references(Map.get(member, :identities, %{}))
    end) ++
      Enum.flat_map(connections, fn connection ->
        references(connection.from) ++ references(connection.to)
      end)
  end

  defp extension_references(extension) do
    [{:extension, extension.provider}] ++ references(extension.data)
  end

  defp optional(_kind, nil), do: []
  defp optional(kind, value), do: [{kind, value}]
end
