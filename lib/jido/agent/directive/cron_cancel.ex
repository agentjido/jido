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
  alias Jido.AgentServer.State

  def exec(%{job_id: logical_id}, _input_signal, state) do
    agent_id = state.id
    proposed_specs = Map.delete(state.cron_specs, logical_id)

    case persist_cron_specs(state, proposed_specs) do
      :ok ->
        {_pid, runtime_state} = drop_runtime_job(state, logical_id)

        new_state = %{runtime_state | cron_specs: proposed_specs}

        Logger.debug(fn ->
          "AgentServer #{agent_id} cancelled cron job #{inspect(logical_id)}"
        end)

        emit_telemetry(new_state, :cancel, %{job_id: logical_id})
        {:ok, new_state}

      {:error, {:invalid_checkpoint, _} = reason} ->
        {_pid, runtime_state} = drop_runtime_job(state, logical_id)
        new_state = %{runtime_state | cron_specs: proposed_specs}

        Logger.error(fn ->
          "AgentServer #{agent_id} cancelled cron job #{inspect(logical_id)} " <>
            "after checkpoint persistence failure: #{inspect(reason)}"
        end)

        emit_telemetry(state, :persist_failure, %{
          job_id: logical_id,
          reason: reason
        })

        emit_telemetry(new_state, :cancel, %{job_id: logical_id})
        {:ok, new_state}

      {:error, reason} ->
        Logger.error(fn ->
          "AgentServer #{agent_id} failed to cancel cron job #{inspect(logical_id)} " <>
            "because persistence failed: #{inspect(reason)}"
        end)

        emit_telemetry(state, :persist_failure, %{
          job_id: logical_id,
          reason: reason
        })

        {:ok, state}
    end
  end

  defp persist_cron_specs(%State{} = state, cron_specs),
    do: Jido.AgentServer.persist_cron_specs(state, cron_specs)

  defp persist_cron_specs(_state, _cron_specs), do: :ok

  defp drop_runtime_job(%State{} = state, logical_id),
    do:
      Jido.AgentServer.untrack_cron_job(state, logical_id,
        cancel?: true,
        drop_runtime_spec?: true
      )

  defp drop_runtime_job(state, logical_id) do
    {Map.get(state.cron_jobs, logical_id),
     %{state | cron_jobs: Map.delete(state.cron_jobs, logical_id)}}
  end

  defp emit_telemetry(%State{} = state, event, metadata),
    do: Jido.AgentServer.emit_cron_telemetry_event(state, event, metadata)

  defp emit_telemetry(_state, _event, _metadata), do: :ok
end
