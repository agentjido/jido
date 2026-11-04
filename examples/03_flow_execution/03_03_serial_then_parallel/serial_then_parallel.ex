defmodule Jido.Examples.Execution.SerialThenParallel.Math do
  use Jido.Action,
    name: "example_exec_serial_then_parallel_math",
    schema:
      Jido.Joi.object(%{
        value: Jido.Joi.integer(),
        factor: Jido.Joi.integer(),
        offset: Jido.Joi.integer()
      }),
    output_schema: Jido.Joi.object(%{value: Jido.Joi.integer()})

  @impl true
  def run(params, _context), do: {:ok, %{value: params.value * params.factor + params.offset}}
end

defmodule Jido.Examples.Execution.SerialThenParallel.Finalize do
  use Jido.Action, name: "example_exec_serial_then_parallel_finalize"

  @impl true
  def run(%{branches: branches}, _context) do
    parallel = Map.new(branches, &{&1.name, &1.value})
    {:ok, %{final: %{value: parallel["plus_ten"].value + 3}, parallel: parallel}}
  end
end

defmodule Jido.Examples.Execution.SerialThenParallel do
  use Jido.Flow,
    name: "example_exec_serial_then_parallel",
    schema: Jido.Joi.object(%{value: Jido.Joi.integer()})

  alias Jido.Examples.Execution.SerialThenParallel.{Finalize, Math}

  flow do
    step "first", action: Math, params: %{value: input(:value), factor: 1, offset: 1}
    step "second", action: Math, params: %{value: result("first", :value), factor: 2, offset: 0}

    parallel "branches" do
      action "plus_ten", Math, params: %{value: result("second", :value), factor: 1, offset: 10}
      action "times_three", Math, params: %{value: result("second", :value), factor: 3, offset: 0}
      action "minus_two", Math, params: %{value: result("second", :value), factor: 1, offset: -2}
    end

    step "third", action: Finalize, params: %{branches: result("branches")}
    output result("third")
  end
end
