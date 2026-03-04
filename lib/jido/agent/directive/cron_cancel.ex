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

    case Map.get(state.cron_jobs, logical_id) do
      nil ->
        Logger.debug(
          "AgentServer #{agent_id} cron job #{inspect(logical_id)} not found, nothing to cancel"
        )

        {:ok, state}

      pid when is_pid(pid) ->
        Jido.Scheduler.cancel(pid)
        Logger.debug("AgentServer #{agent_id} cancelled cron job #{inspect(logical_id)}")

        new_state = %{
          state
          | cron_jobs: Map.delete(state.cron_jobs, logical_id),
            cron_specs: Map.delete(state.cron_specs, logical_id)
        }

        {:ok, new_state}

      _other ->
        Logger.debug(
          "AgentServer #{agent_id} cron job #{inspect(logical_id)} has legacy format, removing from state"
        )

        new_state = %{
          state
          | cron_jobs: Map.delete(state.cron_jobs, logical_id),
            cron_specs: Map.delete(state.cron_specs, logical_id)
        }

        {:ok, new_state}
    end
  end
end
