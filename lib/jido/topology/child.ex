defmodule Jido.Topology.Child do
  @moduledoc false
  alias Jido.Agent.Authoring
  alias Jido.Topology.{Composition, EntryMetadata, Plan, Reference, Validation}

  def source(module, ancestors) when is_atom(module) and not is_nil(module) do
    cond do
      module in ancestors ->
        Authoring.error("Child topology cycle", %{module: module})

      not Code.ensure_loaded?(module) ->
        Authoring.error("Expected a topology module")

      function_exported?(module, :__topology_config__, 0) ->
        director = if module.__topology_owner__?(), do: module.owner()
        {:ok, module.__topology_config__(), director, [module | ancestors]}

      function_exported?(module, :topology, 0) ->
        {:ok, module.topology(), nil, [module | ancestors]}

      true ->
        Authoring.error("Expected a topology module")
    end
  end

  def source(%Jido.Topology{} = value, ancestors), do: {:ok, value, nil, ancestors}

  def source(value, ancestors) when is_map(value) or is_list(value),
    do: {:ok, value, nil, ancestors}

  def source(_, _), do: Authoring.error("Expected a topology module or definition")

  def normalize(attrs, ancestors, depth) do
    with {:ok, attrs} <- Authoring.attrs(attrs),
         :ok <- Authoring.keys(attrs, EntryMetadata.fields(:runtime_child)),
         {:ok, key} <- Validation.key(attrs[:key]),
         {:ok, source, owner, ancestors} <- source(attrs[:topology], ancestors),
         {:ok, topology} <- Validation.definition(source, ancestors, depth + 1),
         topology = struct(Jido.Topology, topology),
         {:ok, director} <- director(Map.get(attrs, :director, owner)),
         {:ok, input} <- Validation.plain_static_map(Map.get(attrs, :input, %{})),
         {:ok, activation} <- activation(Map.get(attrs, :activation, :lazy)),
         {:ok, gate} <- gate(Map.get(attrs, :gate, %{})),
         :ok <- limits(Map.get(attrs, :max_restarts, 3), Map.get(attrs, :max_seconds, 5)) do
      {:ok,
       %{
         key: key,
         topology: topology,
         director: director,
         input: input,
         activation: activation,
         gate: gate,
         max_restarts: Map.get(attrs, :max_restarts, 3),
         max_seconds: Map.get(attrs, :max_seconds, 5)
       }}
    end
  end

  def director(nil), do: {:ok, nil}
  def director(source), do: Validation.agent_definition(source)
  def activation(value) when value in [:eager, :deferred, :lazy], do: {:ok, value}
  def activation(_), do: Authoring.error("Activation must be :eager, :deferred, or :lazy")

  def limits(restarts, seconds)
      when is_integer(restarts) and restarts >= 0 and is_integer(seconds) and seconds > 0,
      do: :ok

  def limits(_, _),
    do: Authoring.error("Expected non-negative max_restarts and positive max_seconds")

  defp gate(attrs) do
    with {:ok, attrs} <- Authoring.attrs(attrs),
         :ok <- Authoring.keys(attrs, [:commands, :events, :to]),
         {:ok, commands} <- Authoring.traverse(Map.get(attrs, :commands, []), &command/1),
         :ok <- unique_commands(commands),
         {:ok, events} <-
           Authoring.traverse(Map.get(attrs, :events, []), fn path ->
             with :ok <- event(path), do: {:ok, path}
           end),
         {:ok, to} <- destination(Map.get(attrs, :to), events) do
      {:ok, %{commands: commands, events: events, to: to}}
    end
  end

  defp destination(nil, []), do: {:ok, nil}

  defp destination(nil, _),
    do: Authoring.error("Exported child events require a parent Bus target")

  defp destination(value, _), do: Jido.Topology.Ref.target(value)

  defp command(attrs) do
    with {:ok, attrs} <- Authoring.attrs(attrs),
         :ok <- Authoring.keys(attrs, [:type, :member]),
         :ok <- event(attrs[:type]),
         {:ok, member} <- target(attrs[:member]) do
      if String.contains?(attrs.type, "*"),
        do: Authoring.error("Child commands require an exact Signal type"),
        else: {:ok, %{type: attrs.type, member: member}}
    end
  end

  defp target({:child, key}) do
    with {:ok, key} <- Validation.key(key), do: {:ok, {:child, key}}
  end

  defp target({:group, key, member}) do
    with {:ok, key} <- Validation.key(key),
         {:ok, member} <- Validation.key(member),
         do: {:ok, {:group, key, member}}
  end

  defp target(value), do: Jido.Topology.Ref.target(value)

  defp unique_commands(commands) do
    if length(commands) == MapSet.size(MapSet.new(commands, & &1.type)),
      do: :ok,
      else: Authoring.error("Duplicate child command")
  end

  defp event(path) when is_binary(path) do
    case Jido.Signal.Router.add(Jido.Signal.Router.new!(), {path, __MODULE__}) do
      {:ok, _} -> :ok
      _ -> Authoring.error("Invalid child event path")
    end
  end

  defp event(_), do: Authoring.error("Expected a child Signal path")

  def validate(definition, parent_plan \\ nil) do
    Authoring.traverse(definition.children, fn child ->
      with {:ok, composed} <- Composition.flatten(child.topology),
           :ok <- commands(child, composed),
           :ok <- parent_bus(child, parent_plan) do
        {:ok, child}
      end
    end)
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp commands(child, composed) do
    Enum.reduce_while(child.gate.commands, :ok, fn command, :ok ->
      valid? =
        case command.member do
          {:child, key} -> Enum.any?(child.topology.children, &(&1.key == key))
          target -> not is_nil(member_key(%{lookup: composed.lookup}, target))
        end

      if valid?, do: {:cont, :ok}, else: {:halt, Authoring.error("Unknown child command member")}
    end)
  end

  defp parent_bus(_child, nil), do: :ok
  defp parent_bus(%{gate: %{to: nil}}, _), do: :ok

  defp parent_bus(child, plan) do
    if Plan.resolve(plan, child.gate.to, :bus),
      do: :ok,
      else: Authoring.error("Unknown parent Bus for child events")
  end

  def plan(definition, id, input, parent_plan) do
    with :ok <- validate(definition, parent_plan),
         {:ok, _} <-
           Authoring.traverse(definition.children, fn child ->
             with {:ok, mapped} <- Reference.resolve(child.input, input),
                  :ok <- validate_director(child.director, id(id, child.key)),
                  {:ok, instance} <-
                    Jido.Topology.instantiate(child.topology,
                      id: id(id, child.key),
                      input: mapped
                    ),
                  :ok <- resolved_commands(child, instance.plan),
                  do: {:ok, child}
           end),
         do: :ok
  end

  def id(parent, key), do: parent <> "/child/" <> Composition.escape(key)
  def depth(%{children: []}), do: 0
  def depth(definition), do: 1 + Enum.max(Enum.map(definition.children, &depth(&1.topology)))
  def validate_director(nil, _), do: :ok

  def validate_director(definition, id) do
    with {:ok, _} <- Jido.Agent.instantiate(definition, id: id <> "/director"), do: :ok
  end

  defp member_key(plan, {:group, group, member}), do: Plan.resolve(plan, group, :agent, member)
  defp member_key(plan, target), do: Plan.resolve(plan, target, :agent)

  defp resolved_commands(child, plan) do
    Enum.reduce_while(child.gate.commands, :ok, fn command, :ok ->
      valid? =
        case command.member do
          {:child, _} -> true
          target -> Map.has_key?(plan.agents, member_key(plan, target))
        end

      if valid?,
        do: {:cont, :ok},
        else: {:halt, Authoring.error("Unknown resolved child command member")}
    end)
  end
end
