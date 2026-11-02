defmodule JidoActionTest.Fixtures.Actions.AtomValidationAction do
  @moduledoc false
  @behaviour Jido.Action
  def validate_params(_params), do: {:error, :bad_params}
  def validate_output(output), do: {:ok, output}
  def run(params, _context), do: {:ok, params}
end

defmodule JidoActionTest.Fixtures.Actions.InvalidValidationResultAction do
  @moduledoc false
  @behaviour Jido.Action
  def validate_params(_params), do: :ok
  def validate_output(output), do: {:ok, output}
  def run(params, _context), do: {:ok, params}
end

defmodule JidoActionTest.Fixtures.Actions.InvalidValidatedParamsAction do
  @moduledoc false
  @behaviour Jido.Action
  def validate_params(_params), do: {:ok, 42}
  def validate_output(output), do: {:ok, output}
  def run(params, _context), do: {:ok, %{params: params}}
end

defmodule JidoActionTest.Fixtures.Actions.InvalidValidatedOutputAction do
  @moduledoc false
  @behaviour Jido.Action
  def validate_params(params), do: {:ok, params}
  def validate_output(_output), do: {:ok, 42}
  def run(_params, _context), do: {:ok, %{value: 1}}
end

defmodule JidoActionTest.Fixtures.Actions.RaisingValidationAction do
  @moduledoc false
  @behaviour Jido.Action
  def validate_params(_params), do: raise("validator failed")
  def validate_output(output), do: {:ok, output}
  def run(params, _context), do: {:ok, params}
end

defmodule JidoActionTest.Fixtures.Actions.RaisingOutputValidationAction do
  @moduledoc false
  @behaviour Jido.Action
  def validate_params(params), do: {:ok, params}
  def validate_output(_output), do: raise("output validator failed")
  def run(params, _context), do: {:ok, params}
end

defmodule JidoActionTest.Fixtures.Actions.StacktraceValidationAction do
  @moduledoc false
  @behaviour Jido.Action

  def validate_params(%{mode: :input}), do: raise_from_input_validator()
  def validate_params(params), do: {:ok, params}

  def validate_output(%{mode: :output}), do: raise_from_output_validator()
  def validate_output(output), do: {:ok, output}

  def run(params, _context), do: {:ok, params}

  def raise_from_input_validator, do: raise("input validator stacktrace probe")
  def raise_from_output_validator, do: raise("output validator stacktrace probe")
end

defmodule JidoActionTest.Fixtures.Actions.ErrorAction do
  @moduledoc false
  use Jido.Action, name: "error_action"

  def run(%{error_type: :validation}, _context), do: {:error, "Validation error"}

  def run(%{error_type: :argument}, _context) do
    raise ArgumentError, message: "Argument error"
  end

  def run(%{error_type: :runtime}, _context) do
    raise RuntimeError, message: "Runtime error"
  end

  def run(%{error_type: :custom}, _context), do: raise("Custom error")
  def run(%{error_type: :throw}, _context), do: throw("Action threw an error")
  def run(_params, _context), do: {:error, "Action failed"}
end

defmodule JidoActionTest.Fixtures.Actions.InvalidOutput do
  @moduledoc false
  use Jido.Action,
    name: "invalid_output",
    description: "Returns invalid output for validation tests",
    schema: Zoi.object(%{value: Zoi.integer()}),
    output_schema: Zoi.object(%{value: Zoi.integer()})

  def run(%{value: value}, _context), do: {:ok, %{value: Integer.to_string(value)}}
end

defmodule JidoActionTest.Fixtures.Actions.UnsupportedResult do
  @moduledoc false
  use Jido.Action,
    name: "unsupported_result",
    description: "Returns an unsupported action result shape"

  def run(_params, _context), do: :not_a_result_tuple
end

defmodule JidoActionTest.Fixtures.Actions.ThrowingAction do
  @moduledoc false
  use Jido.Action,
    name: "throwing_action",
    description: "Throws during execution"

  def run(_params, _context), do: throw(:thrown_value)
end

defmodule JidoActionTest.Fixtures.Actions.StacktraceAction do
  @moduledoc false
  @behaviour Jido.Action

  def validate_params(params), do: {:ok, params}
  def validate_output(output), do: {:ok, output}

  def run(%{mode: :raise}, _context), do: raise_from_action()
  def run(%{mode: :throw}, _context), do: throw_from_action()
  def run(%{mode: :exit}, _context), do: exit_from_action()

  def raise_from_action, do: raise("stacktrace probe raised")
  def throw_from_action, do: throw(:stacktrace_probe_thrown)
  def exit_from_action, do: exit(:stacktrace_probe_exited)
end

defmodule JidoActionTest.Fixtures.Actions.RawOutputAction do
  @moduledoc false
  use Jido.Action, name: "raw_output_action"

  def run(%{value: value}, _context), do: {:ok, value}
end

defmodule JidoActionTest.Fixtures.Actions.RawOutputWithExtrasAction do
  @moduledoc false
  use Jido.Action, name: "raw_output_with_extras_action"

  def run(%{value: value}, _context), do: {:ok, value, [:request]}
end

defmodule JidoActionTest.Fixtures.Actions.ErrorWithExtrasAction do
  @moduledoc false
  use Jido.Action, name: "error_with_extras_action"

  def run(%{reason: reason}, _context), do: {:error, reason, %{ignored: true}}
  def run(_params, _context), do: {:error, :bad_with_extras, %{ignored: true}}
end

defmodule JidoActionTest.Fixtures.Actions.ExceptionErrorAction do
  @moduledoc false
  use Jido.Action, name: "exception_error_action"

  def run(_params, _context) do
    {:error, Jido.Action.Error.execution_error("already wrapped", %{source: :test})}
  end
end

defmodule JidoActionTest.Fixtures.Actions.AtomErrorAction do
  @moduledoc false
  use Jido.Action, name: "atom_error_action"

  def run(_params, _context), do: {:error, :bad_atom}
end

defmodule JidoActionTest.Fixtures.Actions.TupleErrorAction do
  @moduledoc false
  use Jido.Action, name: "tuple_error_action"

  def run(_params, _context), do: {:error, {:bad, :tuple}}
end

defmodule JidoActionTest.Fixtures.Actions.KillingAction do
  @moduledoc false
  use Jido.Action, name: "killing_action"

  def run(_params, _context), do: Process.exit(self(), :kill)
end

defmodule JidoActionTest.Fixtures.ShortListOutputAction do
  @moduledoc false
  use Jido.Action, name: "short_list_output_action"

  @impl true
  def run(_params, _context), do: {:ok, %{items: [%{value: 1}]}}
end

defmodule JidoActionTest.Fixtures.ImproperListOutputAction do
  @moduledoc false
  use Jido.Action, name: "improper_list_output_action"

  @impl true
  def run(_params, _context) do
    {:ok, Jido.Action.Output.raw(%{items: [%{value: 1} | :tail]})}
  end
end

defmodule JidoActionTest.Fixtures.ControlledErrorAction do
  @moduledoc false
  @behaviour Jido.Action

  def validate_params(params), do: {:ok, params}
  def validate_output(output), do: {:ok, output}

  def run(%{message: message} = params, _context) do
    maybe_notify_start(params)
    maybe_block(params)
    {:error, message}
  end

  defp maybe_notify_start(%{key: key, test_pid: test_pid}) do
    send(test_pid, {__MODULE__, :started, key, self()})
  end

  defp maybe_notify_start(_params), do: :ok

  defp maybe_block(%{block: true, key: key}) do
    receive do
      {:release, ^key} -> :ok
    end
  end

  defp maybe_block(_params), do: :ok
end

defmodule JidoActionTest.Fixtures.FailsSecond do
  @moduledoc false
  use Jido.Action,
    name: "iterator_fails_second",
    schema: Zoi.object(%{count: Zoi.integer(), index: Zoi.integer()}),
    output_schema: Zoi.object(%{count: Zoi.integer()})

  @impl true
  def run(%{index: index} = params, context) do
    if is_pid(context[:test_pid]), do: send(context.test_pid, {__MODULE__, index})

    if index == 1 do
      {:error, "second body failed"}
    else
      {:ok, %{count: params.count + 1}}
    end
  end
end

defmodule JidoActionTest.Fixtures.RetryableFailure do
  @moduledoc false
  use Jido.Action,
    name: "iterator_retryable_failure",
    schema: Zoi.object(%{count: Zoi.integer(), index: Zoi.integer()})

  @impl true
  def run(_params, _context) do
    {:error,
     Jido.Action.Error.execution_error("retryable body failed", %{
       retry: true,
       rejected_payload: %{secret: "must not leave the target boundary"}
     })}
  end
end

defmodule JidoActionTest.Fixtures.ReturnedException do
  @moduledoc false
  use Jido.Action,
    name: "iterator_returned_exception",
    schema: Zoi.object(%{count: Zoi.integer(), index: Zoi.integer()})

  @impl true
  def run(_params, _context), do: {:error, RuntimeError.exception("returned body exception")}
end

defmodule JidoActionTest.Fixtures.InvalidOutput do
  @moduledoc false
  use Jido.Action,
    name: "iterator_invalid_output",
    schema: Zoi.object(%{count: Zoi.integer(), index: Zoi.integer()}),
    output_schema: Zoi.object(%{count: Zoi.integer()})

  @impl true
  def run(_params, _context), do: {:ok, %{count: "bad"}}
end
