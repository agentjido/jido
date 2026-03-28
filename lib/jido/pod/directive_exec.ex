defimpl Jido.AgentServer.DirectiveExec, for: Jido.Pod.Directive.ApplyMutation do
  @moduledoc false

  alias Jido.Pod.Runtime

  def exec(%{plan: plan, opts: opts}, _input_signal, state) do
    Runtime.execute_mutation_plan(state, plan, Map.to_list(opts || %{}))
  end
end
