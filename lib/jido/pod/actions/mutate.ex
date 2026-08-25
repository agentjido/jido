defmodule Jido.Pod.Actions.Mutate do
  @moduledoc false

  alias Jido.Pod

  use Jido.Action,
    name: "pod_mutate",
    schema:
      Zoi.object(%{
        ops: Zoi.list(Zoi.any()),
        opts: Zoi.map() |> Zoi.default(%{})
      })

  def run(%{ops: ops, opts: opts}, context) do
    with {:ok, effects} <- Pod.mutation_effects(context.agent, ops, Map.to_list(opts || %{})) do
      mutation_id =
        Enum.find_value(effects, fn
          %Jido.Pod.Directive.ApplyMutation{plan: plan} -> plan.mutation_id
          _other -> nil
        end)

      Pod.mark_mutation_lock(context.agent, context, mutation_id)
      {:ok, %{mutation_queued: true}, effects}
    end
  end
end
