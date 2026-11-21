# These targets omit required callbacks, or declare conflicting behaviours, on
# purpose. test_helper.exs loads this file and captures their expected
# behaviour warnings, so strict test compilation stays warning-free.

defmodule Jido.Test.Action.Fixtures.Actions.MissingRun do
  @moduledoc false
  @behaviour Jido.Action
  def validate_params(params), do: {:ok, params}
  def validate_output(output), do: {:ok, output}
end

defmodule Jido.Test.Action.Fixtures.Actions.MissingValidateParams do
  @moduledoc false
  @behaviour Jido.Action
  def run(params, _context), do: {:ok, params}
  def validate_output(output), do: {:ok, output}
end

defmodule Jido.Test.Action.Fixtures.Actions.MissingValidateOutput do
  @moduledoc false
  @behaviour Jido.Action
  def run(params, _context), do: {:ok, params}
  def validate_params(params), do: {:ok, params}
end

defmodule Jido.Test.Action.InstructionTarget.Ambiguous do
  @moduledoc false
  @behaviour Jido.Action
  @behaviour Jido.Flow

  def run(params, _context), do: {:ok, params}
  def flow, do: Jido.Test.Flow.Fixtures.MathFlow.flow()
  def validate_params(params), do: {:ok, params}
  def validate_output(output), do: {:ok, output}
end

defmodule Jido.Test.Action.InstructionTarget.MissingActionRun do
  @moduledoc false
  @behaviour Jido.Action
  def validate_params(params), do: {:ok, params}
  def validate_output(output), do: {:ok, output}
end

defmodule Jido.Test.Action.InstructionTarget.MissingFlowDefinition do
  @moduledoc false
  @behaviour Jido.Flow
  def validate_params(params), do: {:ok, params}
  def validate_output(output), do: {:ok, output}
end
