defmodule Jido.Examples.Execution.SingleAction.Add do
  use Jido.Action,
    name: "example_exec_single_action_add",
    schema: Jido.Joi.object(%{value: Jido.Joi.integer(), amount: Jido.Joi.integer()}),
    output_schema: Jido.Joi.object(%{value: Jido.Joi.integer(), source: Jido.Joi.string()})

  @impl true
  def run(params, context), do: {:ok, %{value: params.value + params.amount, source: context.source}}
end

defmodule Jido.Examples.Execution.SingleAction.ExplicitOutput do
  use Jido.Action,
    name: "example_exec_single_action_output",
    schema: Jido.Joi.object(%{value: Jido.Joi.string()})

  @impl true
  def run(params, _context),
    do: {:ok, Jido.Action.Output.raw(params.value, meta: %{source: "example"})}
end

defmodule Jido.Examples.Execution.SingleAction.Return do
  use Jido.Action, name: "example_exec_single_action_return"
  @impl true
  def run(%{reply: reply}, _context), do: reply
end

defmodule Jido.Examples.Execution.SingleAction.DirectiveFlow do
  use Jido.Flow, name: "example_exec_single_action_directive_flow"
  alias Jido.Examples.Execution.SingleAction.Return

  flow do
    step "return", action: Return, params: %{reply: input(:reply)}
    output result("return")
  end
end
