defimpl Jido.AgentServer.DirectiveExec, for: Jido.Pod.Directive.ApplyMutation do
  @moduledoc false

  alias Jido.Pod

  def exec(%{plan: plan, opts: opts}, _input_signal, state) do
    Pod.execute_mutation_plan(state, plan, Map.to_list(opts || %{}))
  end
end
