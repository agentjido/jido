defmodule Jido.Examples.Execution.EffectsAndFailure.Add do
  use Jido.Action, name: "example_exec_effect_add"
  @impl true
  def run(params, _context),
    do: {:ok, %{value: params.value + params.amount}, [{:record_add, params.name}]}
end

defmodule Jido.Examples.Execution.EffectsAndFailure.Reject do
  use Jido.Action, name: "example_exec_effect_reject"
  @impl true
  def run(_params, _context) do
    error = Jido.Error.execution_error("planned rejection", %{reason: :planned_rejection})
    {:error, error, [{:must_not_escape, :rejected_work}]}
  end
end

defmodule Jido.Examples.Execution.EffectsAndFailure.Success do
  use Jido.Flow, name: "example_exec_effect_success"
  alias Jido.Examples.Execution.EffectsAndFailure.Add

  flow do
    step "first", action: Add, params: %{name: "first", value: input(:value), amount: 1}
    step "second", action: Add, params: %{name: "second", value: result("first", :value), amount: 2}
    output result("second")
  end
end

defmodule Jido.Examples.Execution.EffectsAndFailure.Failure do
  use Jido.Flow, name: "example_exec_effect_failure"
  alias Jido.Examples.Execution.EffectsAndFailure.{Add, Reject}

  flow do
    step "first", action: Add, params: %{name: "first", value: input(:value), amount: 1}
    step "reject", action: Reject, params: %{value: result("first", :value)}
    output result("reject")
  end
end
