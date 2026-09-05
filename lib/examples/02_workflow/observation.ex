defmodule Jido.Examples.Workflow.Observation do
  @moduledoc """
  Optional observation for the Workflow examples.

  The callback comes from transient caller context. Tests use it to record
  Action entry and hold barriers. It does not replace any SDK component.
  """

  def record(context, stage, value) do
    if callback = context[:on_step], do: callback.(stage, self(), value)
    :ok
  end
end
