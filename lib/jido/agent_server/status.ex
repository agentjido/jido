defmodule Jido.AgentServer.Status do
  @moduledoc """
  Runtime status for an agent process.

  Combines `Strategy.Snapshot` with process-level metadata to provide a clean,
  stable API for querying agent status without depending on internal `__strategy__`
  implementation details.

  ## Fields

  - `agent_module` - The agent's module (e.g., `MyAgent`)
  - `agent_id` - The agent's unique ID
  - `pid` - The GenServer process PID
  - `snapshot` - The `Strategy.Snapshot` containing core status info
  - `raw_state` - Escape hatch containing full agent state (use sparingly)

  ## Usage

      {:ok, agent_status} = AgentServer.status(pid)

      # Check if completed
      if agent_status.snapshot.done? do
        IO.puts("Result: " <> inspect(agent_status.snapshot.result))
      end

      # Access snapshot fields via helpers
      case Status.status(agent_status) do
        :success -> handle_success(agent_status)
        :failure -> handle_failure(agent_status)
        :running -> poll_again()
      end

  ## Delegate Helpers

  The module provides convenience delegates to common snapshot fields:
  - `status/1` - Returns the snapshot's status
  - `done?/1` - Returns the snapshot's done? flag
  - `result/1` - Returns the snapshot's result
  - `details/1` - Returns the snapshot's details map
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              agent_module: Zoi.atom(description: "The agent's module"),
              agent_id: Zoi.string(description: "The agent's unique ID"),
              pid: Zoi.any(description: "The GenServer process PID"),
              snapshot: Zoi.any(description: "The Strategy.Snapshot containing core status"),
              raw_state: Zoi.map(description: "Escape hatch containing full agent state")
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc """
  Creates a new Status from a map of attributes.

  Returns `{:ok, status}` or `{:error, reason}`.
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    Zoi.parse(@schema, attrs)
  end

  def new(_), do: {:error, Jido.Error.validation_error("Status requires a map")}

  @doc "Returns the status from the snapshot (:idle, :running, :waiting, :success, :failure)."
  @spec status(t()) :: Jido.Agent.Strategy.status()
  def status(%__MODULE__{snapshot: s}), do: s.status

  @doc "Returns whether the agent has reached a terminal state."
  @spec done?(t()) :: boolean()
  def done?(%__MODULE__{snapshot: s}), do: s.done?

  @doc "Returns the result from the snapshot (if any)."
  @spec result(t()) :: term() | nil
  def result(%__MODULE__{snapshot: s}), do: s.result

  @doc "Returns strategy-specific details from the snapshot."
  @spec details(t()) :: map()
  def details(%__MODULE__{snapshot: s}), do: s.details

  @doc "Returns the current iteration count from snapshot details."
  @spec iteration(t()) :: non_neg_integer() | nil
  def iteration(%__MODULE__{snapshot: s}), do: s.details[:iteration]

  @doc "Returns the termination reason (e.g., :final_answer, :max_iterations, :error)."
  @spec termination_reason(t()) :: atom() | nil
  def termination_reason(%__MODULE__{snapshot: s}), do: s.details[:termination_reason]

  @doc "Returns the directive queue length."
  @spec queue_length(t()) :: non_neg_integer()
  def queue_length(%__MODULE__{snapshot: s}), do: s.details[:queue_length] || 0

  @doc "Returns active request tuples [{id, status}]."
  @spec active_requests(t()) :: [{String.t(), atom()}]
  def active_requests(%__MODULE__{snapshot: s}), do: s.details[:active_requests] || []
end

defimpl Inspect, for: Jido.AgentServer.Status do
  def inspect(status, _opts) do
    parts =
      [
        status.agent_id,
        ":#{status.snapshot.status}",
        status.snapshot.details[:iteration] && "iter=#{status.snapshot.details[:iteration]}",
        "queue=#{status.snapshot.details[:queue_length] || 0}"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    "#Status<#{parts}>"
  end
end
