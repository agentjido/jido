defmodule Jido.Topology.Plan do
  @moduledoc "An expanded local topology with stable IDs and dependency layers."

  alias Jido.Agent.Authoring
  alias Jido.Topology.{Composition, Ref, Reference, Validation}

  @schema Zoi.struct(__MODULE__, %{
            agents: Zoi.map(),
            resources: Zoi.map(),
            layers: Zoi.list(Zoi.list(Zoi.string())),
            lookup: Zoi.map(),
            components: Zoi.map()
          })
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the plan schema."
  def schema, do: @schema

  @doc false
  def build(definition, id, input) do
    with :ok <- root_imports(definition),
         {:ok, composed} <- Composition.flatten(definition),
         {:ok, inputs} <- Composition.inputs(definition, input),
         {:ok, expanded} <- expand(composed.nodes, inputs, definition.startup.max_agents),
         {:ok, agents} <-
           Authoring.traverse(expanded, &agent(&1, id, Map.fetch!(inputs, &1.scope))),
         {:ok, resources} <-
           Authoring.traverse(
             Enum.filter(composed.nodes, &(&1.kind == :bus)),
             &resource(&1, id, Map.fetch!(inputs, &1.scope))
           ),
         {:ok, components} <- component_limits(composed.scopes, agents, resources) do
      groups = Map.new(Enum.filter(composed.nodes, &(&1.kind == :group)), &{&1.key, []})
      members = Map.merge(groups, Enum.group_by(agents, & &1.declaration, & &1.key))

      agents =
        Enum.map(agents, fn agent ->
          %{
            agent
            | depends_on:
                Enum.flat_map(agent.depends_on, &Map.get(members, &1, [&1])) |> Enum.uniq()
          }
        end)

      dependencies = Map.new(agents ++ resources, &{&1.key, &1.depends_on})

      with {:ok, layers} <- Validation.layers(dependencies),
           do:
             {:ok,
              %__MODULE__{
                agents: Map.new(agents, &{&1.key, &1}),
                resources: Map.new(resources, &{&1.key, &1}),
                layers: layers,
                lookup: composed.lookup,
                components: components
              }}
    end
  end

  defp root_imports(%{imports: []}), do: :ok

  defp root_imports(_),
    do:
      Authoring.error(
        "A root topology cannot have unbound imports; include it and supply bindings"
      )

  defp expand(nodes, inputs, limit) do
    agents = Enum.filter(nodes, &(&1.kind == :agent))
    groups = Enum.filter(nodes, &(&1.kind == :group))

    with :ok <- size_limit(length(agents), limit) do
      Enum.reduce_while(groups, {:ok, [agents], length(agents)}, fn group, {:ok, acc, count} ->
        case expand_group(group, Map.fetch!(inputs, group.scope), limit - count) do
          {:ok, members} -> {:cont, {:ok, [members | acc], count + length(members)}}
          error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, groups, _} -> {:ok, groups |> Enum.reverse() |> List.flatten()}
        error -> error
      end
    end
  end

  defp component_limits(scopes, agents, resources) do
    with {:ok, pairs} <-
           Authoring.traverse(Enum.sort(scopes), fn {path, context} ->
             count = Enum.count(agents, &List.starts_with?(&1.scope, path))

             with :ok <- size_limit(count, context.definition.startup.max_agents),
                  do:
                    {:ok,
                     {path,
                      %{
                        path: path,
                        agents: count,
                        resources: Enum.count(resources, &List.starts_with?(&1.scope, path))
                      }}}
           end),
         do: {:ok, Map.new(pairs)}
  end

  defp expand_group(%{count: count} = group, input, remaining) do
    with {:ok, count} <- Reference.resolve(count, input),
         :ok <- count_valid(count),
         :ok <- size_limit(count, remaining) do
      members =
        if count == 0, do: [], else: Enum.map(1..count, &{Integer.to_string(&1), %{index: &1}})

      {:ok, Enum.map(members, &group_agent(group, &1))}
    end
  end

  defp expand_group(%{members: members, key_by: field} = group, input, remaining) do
    with {:ok, members} <- Reference.resolve(members, input),
         {:ok, keyed} <- Authoring.traverse(members, &keyed_member(&1, field)),
         :ok <- size_limit(length(keyed), remaining),
         :ok <- unique_members(keyed) do
      {:ok, keyed |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&group_agent(group, &1))}
    end
  end

  defp keyed_member(member, field) when is_map(member) and not is_struct(member) do
    with {:ok, key} <- Validation.key(Map.get(member, field)), do: {:ok, {key, member}}
  end

  defp keyed_member(_, _), do: Authoring.error("Group members must be maps with stable keys")

  defp unique_members(members) do
    if length(members) == length(Enum.uniq_by(members, &elem(&1, 0))),
      do: :ok,
      else: Authoring.error("Duplicate group member key")
  end

  defp group_agent(group, {key, member}) do
    group
    |> Map.drop([:count, :members, :key_by])
    |> Map.merge(%{member_key: key, member: member, kind: :agent})
  end

  defp agent(spec, id, input) do
    key =
      if Map.has_key?(spec, :member_key),
        do: spec.key <> "/" <> Composition.escape(spec.member_key),
        else: spec.key

    with {:ok, state} <- Reference.resolve(spec.initial_state, input, Map.get(spec, :member, %{})),
         {:ok, _} <-
           Jido.Agent.new(spec.module, id: Composition.escape(id) <> "/" <> key, state: state) do
      {:ok,
       spec
       |> Map.drop([:member])
       |> Map.merge(%{
         key: key,
         id: Composition.escape(id) <> "/" <> key,
         declaration: spec.key,
         initial_state: state
       })}
    end
  end

  defp resource(spec, id, input) do
    with {:ok, config} <- Reference.resolve(spec.config, input),
         do:
           {:ok,
            Map.merge(spec, %{id: Composition.escape(id) <> "/" <> spec.key, config: config})}
  end

  @doc "Resolves a local declaration or a public child export to a plan key."
  def resolve(plan, target, kind, member \\ nil) do
    with {:ok, target} <- Ref.target(target),
         {:ok, endpoint} <- Map.fetch(plan.lookup, target) do
      case {kind, endpoint.kind, member} do
        {:agent, :agent, nil} ->
          endpoint.key

        {:agent, :group, member} when not is_nil(member) ->
          endpoint.key <> "/" <> Composition.escape(member)

        {:bus, :bus, nil} ->
          endpoint.key

        _ ->
          nil
      end
    else
      _ -> nil
    end
  end

  @doc "Returns a local agent key. Group member keys use an explicit second argument."
  def agent_key(key, member \\ nil)
  def agent_key(key, nil), do: "agent/" <> component(key)
  def agent_key(key, member), do: "group/" <> component(key) <> "/" <> component(member)

  @doc "Returns a local Bus key."
  def bus_key(key), do: "bus/" <> component(key)
  defp component(value), do: URI.encode(to_string(value), &URI.char_unreserved?/1)

  defp count_valid(value) when is_integer(value) and value >= 0, do: :ok
  defp count_valid(_), do: Authoring.error("Resolved group count must be a nonnegative integer")
  defp size_limit(count, limit) when count <= limit, do: :ok
  defp size_limit(_, _), do: Authoring.error("Topology exceeds startup.max_agents")
end
