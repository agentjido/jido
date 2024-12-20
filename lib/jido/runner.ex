defmodule Jido.Runner do
  @moduledoc """
  Behavior for executing planned actions on an Agent.
  """

  @type action :: module() | {module(), map()}
  @callback run(agent :: struct(), actions :: [action()], opts :: keyword()) ::
              {:ok, struct()} | {:error, any()}
end
