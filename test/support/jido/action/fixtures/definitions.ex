defmodule JidoActionTest.Fixtures.Actions.BasicAction do
  @moduledoc false
  use Jido.Action,
    name: "basic_action",
    description: "A basic action for testing",
    schema: Zoi.object(%{value: Zoi.integer()})

  def run(%{value: value}, _context), do: {:ok, %{value: value}}
end

defmodule JidoActionTest.Fixtures.Actions.NoSchema do
  @moduledoc false
  use Jido.Action,
    name: "add_two",
    description: "Adds 2 to the input value"

  def run(%{value: value}, _context), do: {:ok, %{result: value + 2}}
  def run(_params, _context), do: {:ok, %{result: "No params"}}
end

defmodule JidoActionTest.Fixtures.Actions.OutputSchemaAction do
  @moduledoc false
  use Jido.Action,
    name: "output_schema_action",
    description: "Action that validates output with schema",
    schema: Zoi.object(%{input: Zoi.string()}),
    output_schema: Zoi.object(%{result: Zoi.string(), length: Zoi.integer()})

  def run(%{input: input}, _context) do
    {:ok, %{result: String.upcase(input), length: String.length(input), extra: "not validated"}}
  end
end

defmodule JidoActionTest.Fixtures.Actions.NoOutputSchemaAction do
  @moduledoc false
  use Jido.Action,
    name: "no_output_schema_action",
    description: "Action without output schema"

  def run(_params, _context), do: {:ok, %{anything: "goes", here: 123}}
end

defmodule JidoActionTest.Fixtures.Actions.FullAction do
  @moduledoc false
  use Jido.Action,
    name: "full_action",
    description: "A full action for testing",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

  @impl true
  def run(params, _context) do
    result = params.a + params.b
    {:ok, Map.put(params, :result, result)}
  end
end

defmodule JidoActionTest.Fixtures.Actions.Add do
  @moduledoc false
  use Jido.Action,
    name: "add_one",
    description: "Adds 1 to the input value",
    schema: Zoi.object(%{value: Zoi.integer(), amount: Zoi.integer() |> Zoi.default(1)}),
    output_schema: Zoi.object(%{value: Zoi.integer()})

  def run(%{value: value, amount: amount}, _context), do: {:ok, %{value: value + amount}}
end

defmodule JidoActionTest.Fixtures.Actions.Multiply do
  @moduledoc false
  use Jido.Action,
    name: "multiply",
    description: "Multiplies the input value by 2",
    schema: Zoi.object(%{value: Zoi.integer(), amount: Zoi.integer() |> Zoi.default(2)})

  def run(%{value: value, amount: amount}, _context), do: {:ok, %{value: value * amount}}
end

defmodule JidoActionTest.Fixtures.Actions.Divide do
  @moduledoc false
  use Jido.Action,
    name: "divide",
    description: "Divides first value by second value",
    schema: Zoi.object(%{value: Zoi.float(), amount: Zoi.float() |> Zoi.default(2.0)})

  def run(%{value: value, amount: amount}, _context) when amount != 0 do
    {:ok, %{value: value / amount}}
  end

  def run(_params, _context), do: raise("Cannot divide by zero")
end

defmodule JidoActionTest.Fixtures.Actions.ContextEcho do
  @moduledoc false
  use Jido.Action,
    name: "context_echo",
    description: "Echoes runtime context",
    schema: Zoi.object(%{value: Zoi.integer()}),
    output_schema: Zoi.object(%{value: Zoi.integer(), trace_id: Zoi.string()})

  def run(%{value: value}, %{trace_id: trace_id}) do
    {:ok, %{value: value, trace_id: trace_id}}
  end
end

defmodule JidoActionTest.Fixtures.Actions.EchoParamsAction do
  @moduledoc false
  use Jido.Action, name: "echo_params_action"

  def run(params, _context), do: {:ok, params}
end

defmodule JidoActionTest.Fixtures.Actions.ExtrasAction do
  @moduledoc false
  use Jido.Action,
    name: "extras_action",
    description: "Returns a normal action output with extras",
    schema: Zoi.object(%{value: Zoi.integer()}),
    output_schema: Zoi.object(%{value: Zoi.integer()})

  def run(%{value: value}, context) do
    {:ok, %{value: value}, [%{trace_id: Map.get(context, :trace_id)}]}
  end
end

defmodule JidoActionTest.Fixtures.Actions.NoneExtrasAction do
  @moduledoc false
  use Jido.Action, name: "none_extras_action"

  def run(params, _context), do: {:ok, params, :none}
end

defmodule JidoActionTest.Fixtures.Actions.OutputEnvelopeAction do
  @moduledoc false
  use Jido.Action,
    name: "output_envelope_action",
    description: "Returns an explicit action output envelope",
    schema: Zoi.object(%{value: Zoi.integer()})

  def run(%{value: value}, _context) do
    {:ok, Jido.Action.Output.raw(%{value: value}, meta: %{source: :test})}
  end
end

defmodule JidoActionTest.Fixtures.Actions.MapProbeAction do
  @moduledoc false
  use Jido.Action, name: "map_probe_action"

  def run(%{test_pid: test_pid, index: index} = params, _context) when is_pid(test_pid) do
    send(test_pid, {__MODULE__, :started, index, self()})

    if Map.get(params, :block, false) do
      receive do
        :release -> :ok
      end
    end

    case Map.get(params, :outcome, :ok) do
      :ok ->
        output = %{index: index, value: Map.get(params, :value)}

        if Map.get(params, :extras, false) do
          {:ok, output, [:request]}
        else
          {:ok, output}
        end

      {:error, message} ->
        {:error, message}

      :kill ->
        Process.exit(self(), :kill)
    end
  end
end

defmodule JidoActionTest.Fixtures.Actions.CountedMapAction do
  @moduledoc false
  @behaviour Jido.Action

  def validate_params(%{test_pid: test_pid, index: index} = params) do
    send(test_pid, {__MODULE__, :input, index})
    {:ok, params}
  end

  def run(%{test_pid: test_pid, index: index} = params, _context) do
    send(test_pid, {__MODULE__, :run, index})
    {:ok, params}
  end

  def validate_output(%{test_pid: test_pid, index: index} = output) do
    send(test_pid, {__MODULE__, :output, index})
    {:ok, output}
  end
end

defmodule JidoActionTest.Fixtures.Actions.ReduceProbeAction do
  @moduledoc false
  use Jido.Action, name: "reduce_probe_action"

  def run(
        %{
          accumulator: accumulator,
          item: item,
          index: index,
          item_id: item_id
        } = params,
        context
      ) do
    if test_pid = Map.get(context, :test_pid) do
      send(test_pid, {__MODULE__, :called, index, item_id, item, accumulator})
    end

    case Map.get(params, :outcome, :map) do
      :map ->
        values = Map.get(accumulator, :values, [])

        {:ok, %{values: values ++ [item], indexes: Map.get(accumulator, :indexes, []) ++ [index]}}

      :subtract ->
        {:ok, %{value: Map.fetch!(accumulator, :value) - item}}

      :output ->
        values = accumulator.value.values
        {:ok, Jido.Action.Output.raw(%{values: values ++ [item]}, meta: %{source: :reduce})}

      :scalar ->
        {:ok, :invalid_reduce_output}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

defmodule JidoActionTest.Fixtures.Actions.RecorderAction do
  @moduledoc false
  use Jido.Action, name: "recorder_action"

  def run(params, %{test_pid: test_pid}) when is_pid(test_pid) do
    send(test_pid, {__MODULE__, params})
    {:ok, params}
  end

  def run(params, _context), do: {:ok, params}
end

defmodule JidoActionTest.Fixtures.ActionWithFlowFunction do
  @moduledoc false
  use Jido.Action, name: "action_with_flow_function"

  def flow, do: :not_a_flow_artifact
  def run(params, _context), do: {:ok, Map.put(params, :executed_as, :action)}
end

defmodule JidoActionTest.Fixtures.ListOutputAction do
  @moduledoc false
  use Jido.Action, name: "list_output_action"

  @impl true
  def run(_params, _context), do: {:ok, %{items: [%{value: 1}, %{value: 2}]}}
end

defmodule JidoActionTest.Fixtures.ConcurrencyProbeAction do
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

defmodule JidoActionTest.Fixtures.Increment do
  @moduledoc false
  use Jido.Action,
    name: "iterator_increment",
    schema: Zoi.object(%{count: Zoi.integer(), index: Zoi.integer()}),
    output_schema: Zoi.object(%{count: Zoi.integer()})

  @impl true
  def run(%{count: count, index: index}, context) do
    if is_pid(context[:test_pid]), do: send(context.test_pid, {__MODULE__, index})
    {:ok, %{count: count + 1}}
  end
end

defmodule JidoActionTest.Fixtures.Envelope do
  @moduledoc false
  use Jido.Action,
    name: "iterator_envelope",
    schema: Zoi.object(%{count: Zoi.integer(), index: Zoi.integer()})

  @impl true
  def run(%{count: count}, _context) do
    {:ok, Jido.Action.Output.raw(%{count: count + 1}, meta: %{source: :iterate_test})}
  end
end

defmodule JidoActionTest.Fixtures.StateStruct do
  @moduledoc false
  @enforce_keys [:count]
  defstruct [:count]
end
