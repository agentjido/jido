defmodule Jido.AgentServer.Pending do
  @moduledoc """
  An owner-bound handle for one submitted Turn result.

  The handle is local and ephemeral. It does not contain a process handle and
  it cannot be transferred to another process.
  """

  @enforce_keys [:turn_id, :request_id]
  @derive {Inspect, only: [:turn_id, :request_id]}
  defstruct [:turn_id, :request_id]

  @type t :: %__MODULE__{
          turn_id: String.t(),
          request_id: String.t()
        }
end
