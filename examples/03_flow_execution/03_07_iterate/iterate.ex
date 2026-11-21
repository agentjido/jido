defmodule Jido.Examples.Execution.Iterate.Advance do
  use Jido.Action, name: "example_exec_iterate_advance"

  @impl true
  def run(%{count: count}, _context), do: {:ok, %{count: count + 1}}
end

defmodule Jido.Examples.Execution.Iterate do
  use Jido.Flow, name: "example_exec_iterate"
  alias Jido.Examples.Execution.Iterate.Advance

  flow do
    iterate "counter" do
      state Jido.Joi.object(%{count: Jido.Joi.integer()}), initial: %{count: input(:start)}
      action Advance
      params %{count: state(:count)}
      update body_result()
      while state(:count) < input(:target)
      max_iterations 4
    end

    output result("counter")
  end
end
