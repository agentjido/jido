defmodule Jido.Statechart.Configuration do
  @moduledoc false

  def atomic?(chart, id), do: chart.states[id].kind in [:atomic, :final]

  def final?(chart, configuration, id) do
    case chart.states[id] do
      %{kind: :compound, children: children} ->
        Enum.any?(children, &(chart.states[&1].kind == :final and &1 in configuration))

      %{kind: :parallel, children: children} ->
        Enum.all?(children, &final?(chart, configuration, &1))

      _ ->
        false
    end
  end

  def ancestors(_chart, nil), do: []

  def ancestors(chart, id) do
    case (chart.states[id] || chart.histories[id]).parent do
      nil -> []
      parent -> [parent | ancestors(chart, parent)]
    end
  end

  def descendant?(_chart, id, nil), do: not is_nil(id)
  def descendant?(chart, id, ancestor), do: ancestor in ancestors(chart, id)

  def select(chart, %{configuration: configuration, history: history}, work, enabled) do
    {candidates, work} =
      configuration
      |> Enum.filter(&atomic?(chart, &1))
      |> Enum.map_reduce(work, fn id, work ->
        transitions =
          for source <- [id | ancestors(chart, id)],
              transition <- chart.states[source].transitions do
            Map.put(transition, :source, source)
          end

        Enum.reduce_while(transitions, {nil, work}, fn transition, {nil, work} ->
          case enabled.(transition, work) do
            {true, work} -> {:halt, {transition, work}}
            {false, work} -> {:cont, {nil, work}}
          end
        end)
      end)

    selected =
      candidates
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.reduce([], fn transition, selected ->
        {targets, _blocks} = resolve_targets(chart, history, transition.targets)
        exits = exit_set(chart, configuration, %{transition | targets: targets})

        {conflicts, others} =
          Enum.split_with(selected, &Enum.any?(&1.exits, fn id -> id in exits end))

        if Enum.all?(conflicts, &descendant?(chart, transition.source, &1.source)),
          do: others ++ [Map.put(transition, :exits, exits)],
          else: selected
      end)

    {selected, work}
  end

  defp exit_set(_chart, _configuration, %{targets: []}), do: []

  defp exit_set(chart, configuration, %{source: source, targets: targets, type: type}) do
    domain =
      if type == "internal" and chart.states[source].kind == :compound and
           Enum.all?(targets, &descendant?(chart, &1, source)) do
        source
      else
        Enum.find(ancestors(chart, source), fn ancestor ->
          chart.states[ancestor].kind == :compound and
            Enum.all?(targets, &descendant?(chart, &1, ancestor))
        end)
      end

    Enum.filter(configuration, &descendant?(chart, &1, domain))
  end

  def remember(chart, %{configuration: active, history: history}, exits) do
    Enum.reduce(chart.histories, history, fn {id, state}, history ->
      if MapSet.member?(exits, state.parent) do
        saved =
          Enum.filter(active, fn active_id ->
            case state.type do
              "shallow" -> chart.states[active_id].parent == state.parent
              "deep" -> atomic?(chart, active_id) and descendant?(chart, active_id, state.parent)
            end
          end)

        Map.put(history, id, saved)
      else
        history
      end
    end)
  end

  def plan(chart, %{configuration: retained, history: history}, targets) do
    {targets, blocks} = resolve_targets(chart, history, targets)
    plan = plan_children(chart, chart.roots, retained ++ targets, history, blocks)
    ids = MapSet.new(plan, &elem(&1, 0))

    if Enum.all?(ids, fn id ->
         case chart.states[id] do
           %{kind: :compound, children: children} ->
             Enum.count(children, &MapSet.member?(ids, &1)) == 1

           _ ->
             true
         end
       end) and Enum.count(chart.roots, &MapSet.member?(ids, &1)) == 1 do
      {:ok, plan}
    else
      {:error, :illegal_state_configuration}
    end
  end

  defp resolve_targets(chart, history, targets) do
    Enum.reduce(targets, {[], %{}}, fn id, {targets, blocks} ->
      case chart.histories[id] do
        nil ->
          {targets ++ [id], blocks}

        state ->
          case Map.fetch(history, id) do
            {:ok, remembered} ->
              {targets ++ remembered, blocks}

            :error ->
              %{targets: defaults, actions: actions} = state.initial

              {targets ++ defaults, Map.update(blocks, state.parent, [actions], &(&1 ++ [actions]))}
          end
      end
    end)
  end

  defp plan_state(chart, id, requested, history, blocks) do
    state = chart.states[id]

    case state.kind do
      :compound ->
        case Enum.filter(requested, &descendant?(chart, &1, id)) do
          [] ->
            %{targets: targets, actions: actions} = state.initial
            {targets, defaults} = resolve_targets(chart, history, targets)
            blocks = Map.merge(blocks, defaults, fn _id, left, right -> left ++ right end)
            entry = {id, [actions | Map.get(blocks, id, [])]}
            [entry | plan_children(chart, state.children, targets, history, blocks)]

          targets ->
            entry = {id, Map.get(blocks, id, [])}
            [entry | plan_children(chart, state.children, targets, history, blocks)]
        end

      :parallel ->
        entry = {id, Map.get(blocks, id, [])}

        [
          entry
          | Enum.flat_map(state.children, &plan_state(chart, &1, requested, history, blocks))
        ]

      _leaf ->
        [{id, []}]
    end
  end

  defp plan_children(chart, children, requested, history, blocks) do
    children
    |> covered_children(chart, requested)
    |> Enum.flat_map(&plan_state(chart, &1, requested, history, blocks))
  end

  defp covered_children(children, chart, requested) do
    Enum.filter(children, fn child ->
      Enum.any?(requested, &(&1 == child or descendant?(chart, &1, child)))
    end)
  end
end
