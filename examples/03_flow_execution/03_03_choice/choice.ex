defmodule Jido.Examples.Execution.Choice.Label do
  use Jido.Action, name: "example_exec_choice_label"

  @impl true
  def run(params, _context), do: {:ok, params}
end

defmodule Jido.Examples.Execution.Choice do
  use Jido.Flow,
    name: "example_exec_choice",
    schema: Jido.Joi.object(%{score: Jido.Joi.integer()})

  alias Jido.Examples.Execution.Choice.Label

  flow do
    choice "grade" do
      option "excellent", condition: input(:score) >= 90, action: Label, params: %{label: "excellent"}
      option "passing", condition: input(:score) >= 60, action: Label, params: %{label: "passing"}
      otherwise action: Label, params: %{label: "needs_work"}
    end

    output result("grade")
  end
end
