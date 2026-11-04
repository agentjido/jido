defmodule Jido.Examples.Execution.Parallel.Check do
  use Jido.Action,
    name: "example_exec_parallel_check",
    schema: Jido.Joi.object(%{name: Jido.Joi.string(), value: Jido.Joi.integer()}),
    output_schema: Jido.Joi.object(%{name: Jido.Joi.string(), value: Jido.Joi.integer()})

  @impl true
  def run(params, %{observer: observer, gate: gate, probe: probe}) do
    Agent.update(probe, fn state ->
      active = state.active + 1
      %{state | active: active, max_active: max(state.max_active, active), started: [params.name | state.started]}
    end)

    send(observer, {:parallel_ready, params.name, self()})
    receive do: ({:release_parallel, ^gate} -> :ok)
    Agent.update(probe, &%{&1 | active: &1.active - 1})
    {:ok, %{name: params.name, value: params.value * 2}}
  end

  def run(params, _context), do: {:ok, %{name: params.name, value: params.value * 2}}
end

defmodule Jido.Examples.Execution.Parallel.Index do
  use Jido.Action, name: "example_exec_parallel_index"

  @impl true
  def run(%{checks: checks}, _context), do: {:ok, Map.new(checks, &{&1.name, &1.value})}
end

defmodule Jido.Examples.Execution.Parallel do
  use Jido.Flow,
    name: "example_exec_parallel",
    schema:
      Jido.Joi.object(%{
        left: Jido.Joi.integer(),
        middle: Jido.Joi.integer(),
        right: Jido.Joi.integer()
      })

  alias Jido.Examples.Execution.Parallel.{Check, Index}

  flow do
    parallel "checks" do
      action "left", Check, params: %{name: "left", value: input(:left)}
      action "middle", Check, params: %{name: "middle", value: input(:middle)}
      action "right", Check, params: %{name: "right", value: input(:right)}
    end

    step "indexed", action: Index, params: %{checks: result("checks")}
    output %{checks: result("indexed")}
  end
end
