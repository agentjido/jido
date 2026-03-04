defmodule Jido.Agent.Directive.CronCancel do
  @moduledoc """
  Cancel a previously registered cron job for this agent by job_id.

  ## Fields

  - `job_id` - The logical job id to cancel

  ## Examples

      %CronCancel{job_id: :heartbeat}
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              job_id: Zoi.any(description: "Logical cron job id within the agent")
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for CronCancel."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.CronCancel do
  @moduledoc false

  require Logger

  def exec(%{job_id: logical_id}, _input_signal, state) do
    agent_id = state.id
    proposed_specs = Map.delete(state.cron_specs, logical_id)

    case Jido.AgentServer.persist_cron_specs(state, proposed_specs) do
      :ok ->
        {_pid, runtime_state} =
          Jido.AgentServer.untrack_cron_job(state, logical_id, cancel?: true)

        new_state = %{runtime_state | cron_specs: proposed_specs}

        Logger.debug("AgentServer #{agent_id} cancelled cron job #{inspect(logical_id)}")

        Jido.AgentServer.emit_cron_telemetry_event(new_state, :cancel, %{job_id: logical_id})
        {:ok, new_state}

      {:error, reason} ->
        Logger.error(
          "AgentServer #{agent_id} failed to persist cron cancellation for #{inspect(logical_id)}: #{inspect(reason)}"
        )

        Jido.AgentServer.emit_cron_telemetry_event(state, :persist_failure, %{
          job_id: logical_id,
          reason: reason
        })

        {:ok, state}
    end
  end
end
