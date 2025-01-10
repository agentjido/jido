defmodule Jido.Runner do
  @moduledoc """
  Behavior for executing planned actions on an Agent.
  """

  alias Jido.Runner.Result

  @type action :: module() | {module(), map()}

  @callback run(agent :: struct(), opts :: keyword()) ::
              {:ok, Result.t()} | {:error, Jido.Error.t()}
end
