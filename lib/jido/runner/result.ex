defmodule Jido.Runner.Result do
  @moduledoc """
  Represents the result of executing one or more instructions.
  Contains the final state and any directives for the agent.

  The Result struct tracks:
  - Initial and final state of the execution
  - Status and any errors that occurred
  - Instructions that were executed
  - Any directives generated during execution
  - Remaining pending instructions

  This is used by both the Simple and Chain runners to maintain execution state
  and return results in a consistent format.
  """
  use TypedStruct
  alias Jido.Error

  @derive Jason.Encoder
  @derive Inspect
  typedstruct enforce: true do
    field(:id, String.t(), default: Jido.Util.generate_id())
    field(:initial_state, map(), default: %{})
    field(:result_state, map(), default: %{})
    field(:status, atom(), default: :ok)
    field(:error, Error.t(), default: nil)
    field(:instructions, list(), default: [])
    field(:directives, list(), default: [])
    field(:syscalls, list(), default: [])
    field(:pending_instructions, :queue.queue(), default: :queue.new())
  end
end
