defmodule Jido.Test.Action.Fixtures.Actions.AtomValidationAction do
  @moduledoc false
  @behaviour Jido.Action
  def validate_params(_params), do: {:error, :bad_params}
  def validate_output(output), do: {:ok, output}
  def run(params, _context), do: {:ok, params}
end

defmodule Jido.Test.Action.Fixtures.Actions.InvalidValidationResultAction do
  @moduledoc false
  @behaviour Jido.Action
  def validate_params(_params), do: :ok
  def validate_output(output), do: {:ok, output}
  def run(params, _context), do: {:ok, params}
end

defmodule Jido.Test.Action.Fixtures.Actions.StacktraceValidationAction do
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

defmodule Jido.Test.Action.Fixtures.Actions.ErrorAction do
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

defmodule Jido.Test.Action.Fixtures.Actions.InvalidOutput do
  @moduledoc false
  use Jido.Action,
    name: "invalid_output",
    description: "Returns invalid output for validation tests",
    schema: Jido.Joi.object(%{value: Jido.Joi.integer()}),
    output_schema: Jido.Joi.object(%{value: Jido.Joi.integer()})

  def run(%{value: value}, _context), do: {:ok, %{value: Integer.to_string(value)}}
end

defmodule Jido.Test.Action.Fixtures.Actions.UnsupportedResult do
  @moduledoc false
  use Jido.Action,
    name: "unsupported_result",
    description: "Returns an unsupported action result shape"

  def run(_params, _context), do: :not_a_result_tuple
end

defmodule Jido.Test.Action.Fixtures.Actions.StacktraceAction do
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

defmodule Jido.Test.Action.Fixtures.Actions.ErrorWithExtrasAction do
  @moduledoc false
  use Jido.Action, name: "error_with_extras_action"

  def run(%{reason: reason}, _context), do: {:error, reason, %{ignored: true}}
  def run(_params, _context), do: {:error, :bad_with_extras, %{ignored: true}}
end

defmodule Jido.Test.Action.Fixtures.Actions.TupleErrorAction do
  @moduledoc false
  use Jido.Action, name: "tuple_error_action"

  def run(_params, _context), do: {:error, {:bad, :tuple}}
end

defmodule Jido.Test.Action.Fixtures.Actions.KillingAction do
  @moduledoc false
  use Jido.Action, name: "killing_action"

  def run(_params, _context), do: Process.exit(self(), :kill)
end

defmodule Jido.Test.Action.Fixtures.InvalidOutput do
  @moduledoc false
  use Jido.Action,
    name: "iterator_invalid_output",
    schema: Jido.Joi.object(%{count: Jido.Joi.integer(), index: Jido.Joi.integer()}),
    output_schema: Jido.Joi.object(%{count: Jido.Joi.integer()})

  @impl true
  def run(_params, _context), do: {:ok, %{count: "bad"}}
end
