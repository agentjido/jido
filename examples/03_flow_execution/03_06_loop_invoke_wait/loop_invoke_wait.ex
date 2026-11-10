defmodule Jido.Examples.Execution.LoopInvokeWait.Advance do
  use Jido.Action, name: "example_exec_loop_advance"
  @impl true
  def run(%{count: count, index: index}, _context),
    do: {:ok, %{count: count + 1}, [{:attempt, index}]}
end

defmodule Jido.Examples.Execution.LoopInvokeWait.Approval do
  use Jido.Flow, name: "example_exec_wait_for_approval"

  flow do
    await "approval", event: "request.approved", match: %{request_id: input(:request_id)}
    output result("approval")
  end
end

defmodule Jido.Examples.Execution.LoopInvokeWait do
  use Jido.Flow, name: "example_exec_loop_invoke_wait"
  alias Jido.Examples.Execution.LoopInvokeWait.{Advance, Approval}

  flow do
    iterate "attempts" do
      state Jido.Joi.object(%{count: Jido.Joi.integer()}), initial: %{count: 0}
      action Advance
      params %{count: state(:count), index: iteration_index()}
      update body_result()
      repeat 2
    end

    step "approval", action: Approval, params: %{request_id: input(:request_id)}, needs: ["attempts"]
    output %{attempts: result("attempts"), approval: result("approval")}
  end
end
