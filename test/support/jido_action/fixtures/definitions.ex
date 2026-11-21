defmodule Jido.Test.Action.Fixtures.Actions.BasicAction do
  @moduledoc false
  use Jido.Action,
    name: "basic_action",
    description: "A basic action for testing",
    schema: Jido.Joi.object(%{value: Jido.Joi.integer()})

  def run(%{value: value}, _context), do: {:ok, %{value: value}}
end

defmodule Jido.Test.Action.Fixtures.Actions.NoSchema do
  @moduledoc false
  use Jido.Action,
    name: "add_two",
    description: "Adds 2 to the input value"

  def run(%{value: value}, _context), do: {:ok, %{result: value + 2}}
  def run(_params, _context), do: {:ok, %{result: "No params"}}
end

defmodule Jido.Test.Action.Fixtures.Actions.OutputSchemaAction do
  @moduledoc false
  use Jido.Action,
    name: "output_schema_action",
    description: "Action that validates output with schema",
    schema: Jido.Joi.object(%{input: Jido.Joi.string()}),
    output_schema: Jido.Joi.object(%{result: Jido.Joi.string(), length: Jido.Joi.integer()})

  def run(%{input: input}, _context) do
    {:ok, %{result: String.upcase(input), length: String.length(input), extra: "not validated"}}
  end
end

defmodule Jido.Test.Action.Fixtures.Actions.NoOutputSchemaAction do
  @moduledoc false
  use Jido.Action,
    name: "no_output_schema_action",
    description: "Action without output schema"

  def run(_params, _context), do: {:ok, %{anything: "goes", here: 123}}
end

defmodule Jido.Test.Action.Fixtures.Actions.FullAction do
  @moduledoc false
  use Jido.Action,
    name: "full_action",
    description: "A full action for testing",
    schema: Jido.Joi.object(%{a: Jido.Joi.integer(), b: Jido.Joi.integer()})

  @impl true
  def run(params, _context) do
    result = params.a + params.b
    {:ok, Map.put(params, :result, result)}
  end
end

defmodule Jido.Test.Action.Fixtures.Actions.Add do
  @moduledoc false
  use Jido.Action,
    name: "add_one",
    description: "Adds 1 to the input value",
    schema: Jido.Joi.object(%{value: Jido.Joi.integer(), amount: Jido.Joi.integer() |> Jido.Joi.default(1)}),
    output_schema: Jido.Joi.object(%{value: Jido.Joi.integer()})

  def run(%{value: value, amount: amount}, _context), do: {:ok, %{value: value + amount}}
end

defmodule Jido.Test.Action.Fixtures.Actions.Multiply do
  @moduledoc false
  use Jido.Action,
    name: "multiply",
    description: "Multiplies the input value by 2",
    schema: Jido.Joi.object(%{value: Jido.Joi.integer(), amount: Jido.Joi.integer() |> Jido.Joi.default(2)})

  def run(%{value: value, amount: amount}, _context), do: {:ok, %{value: value * amount}}
end

defmodule Jido.Test.Action.Fixtures.Actions.ContextEcho do
  @moduledoc false
  use Jido.Action,
    name: "context_echo",
    description: "Echoes runtime context",
    schema: Jido.Joi.object(%{value: Jido.Joi.integer()}),
    output_schema: Jido.Joi.object(%{value: Jido.Joi.integer(), trace_id: Jido.Joi.string()})

  def run(%{value: value}, %{trace_id: trace_id}) do
    {:ok, %{value: value, trace_id: trace_id}}
  end
end

defmodule Jido.Test.Action.Fixtures.Actions.EchoParamsAction do
  @moduledoc false
  use Jido.Action, name: "echo_params_action"

  def run(params, _context), do: {:ok, params}
end

defmodule Jido.Test.Action.Fixtures.Actions.ExtrasAction do
  @moduledoc false
  use Jido.Action,
    name: "extras_action",
    description: "Returns a normal action output with extras",
    schema: Jido.Joi.object(%{value: Jido.Joi.integer()}),
    output_schema: Jido.Joi.object(%{value: Jido.Joi.integer()})

  def run(%{value: value}, context) do
    {:ok, %{value: value}, [%{trace_id: Map.get(context, :trace_id)}]}
  end
end

defmodule Jido.Test.Action.Fixtures.ActionWithFlowFunction do
  @moduledoc false
  use Jido.Action, name: "action_with_flow_function"

  def flow, do: :not_a_flow_artifact
  def run(params, _context), do: {:ok, Map.put(params, :executed_as, :action)}
end

defmodule Jido.Test.Action.Fixtures.ConcurrencyProbeAction do
  @moduledoc false
  @behaviour Jido.Action

  def validate_params(params), do: {:ok, params}
  def validate_output(output), do: {:ok, output}

  def run(%{probe: probe, side: side, test_pid: test_pid}, _context) do
    Agent.update(probe, fn %{max: max, running: running} = state ->
      running = running + 1
      %{state | max: Kernel.max(max, running), running: running}
    end)

    send(test_pid, {__MODULE__, :started, probe, side, self()})

    result =
      receive do
        {:release, ^probe} -> {:ok, %{side: side}}
      after
        4_000 -> {:error, "concurrency probe was not released"}
      end

    Agent.update(probe, &Map.update!(&1, :running, fn running -> running - 1 end))
    result
  end
end
