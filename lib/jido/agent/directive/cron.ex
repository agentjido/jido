defmodule Jido.Agent.Directive.Cron do
  @moduledoc """
  Register or update a recurring cron job for this agent.

  The job is owned by the agent's `id` and identified within that agent
  by `job_id`. On each tick, the scheduler sends `message` (or `signal`)
  back to the agent via `Jido.AgentServer.cast/2`.

  ## Fields

  - `job_id` - Logical id within the agent (for upsert/cancel). Auto-generated if nil.
  - `cron` - Cron expression string (e.g., "* * * * *", "@daily", "*/5 * * * *")
  - `message` - Signal or message to send on each tick
  - `timezone` - Optional timezone identifier (default: UTC)

  ## Examples

      # Every minute, send a tick signal
      %Cron{cron: "* * * * *", message: tick_signal, job_id: :heartbeat}

      # Daily at midnight, send a cleanup signal
      %Cron{cron: "@daily", message: cleanup_signal, job_id: :daily_cleanup}

      # Every 5 minutes with timezone
      %Cron{cron: "*/5 * * * *", message: check_signal, job_id: :check, timezone: "America/New_York"}
  """

  require Logger

  alias Jido.AgentServer
  alias Jido.AgentServer.CronRuntimeSpec

  @schema Zoi.struct(
            __MODULE__,
            %{
              job_id:
                Zoi.any(description: "Logical cron job id within the agent")
                |> Zoi.optional(),
              cron: Zoi.any(description: "Cron expression (e.g. \"* * * * *\", \"@daily\")"),
              message: Zoi.any(description: "Signal or message to send on each tick"),
              timezone:
                Zoi.any(description: "Timezone identifier (optional)")
                |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Cron."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc false
  @spec register(map(), term(), term(), term(), term(), keyword()) :: {:ok, map()}
  def register(state, cron_expr, message, logical_id, tz, opts \\ []) do
    on_failure = Keyword.get(opts, :on_failure, :keep)
    agent_id = state.id
    logical_id = logical_id || make_ref()

    with {:ok, cron_spec} <- Jido.Scheduler.validate_and_build_cron_spec(cron_expr, message, tz),
         runtime_spec =
           CronRuntimeSpec.dynamic(
             cron_spec.cron_expression,
             cron_spec.message,
             cron_spec.timezone
           ),
         {:ok, pid} <- AgentServer.start_runtime_cron_job(state, logical_id, runtime_spec),
         {:ok, persisted_state} <-
           persist_then_commit_registration(state, pid, logical_id, cron_spec, runtime_spec) do
      Logger.debug(fn ->
        "AgentServer #{agent_id} registered cron job #{inspect(logical_id)}: #{cron_expr}"
      end)

      AgentServer.emit_cron_telemetry_event(persisted_state, :register, %{
        job_id: logical_id,
        cron_expression: cron_expr
      })

      {:ok, persisted_state}
    else
      {:error, reason} ->
        Logger.error(fn ->
          "AgentServer #{agent_id} failed to register cron job #{inspect(logical_id)}: #{inspect(reason)}"
        end)

        {:ok, handle_failed_registration(state, logical_id, on_failure)}
    end
  end

  defp persist_then_commit_registration(state, new_pid, logical_id, cron_spec, runtime_spec) do
    proposed_specs = Map.put(state.cron_specs, logical_id, cron_spec)

    case AgentServer.persist_cron_specs(state, proposed_specs) do
      :ok ->
        tracked_state =
          AgentServer.track_cron_job(state, logical_id, new_pid, runtime_spec: runtime_spec)

        committed_state = %{tracked_state | cron_specs: proposed_specs}

        {:ok, committed_state}

      {:error, {:invalid_checkpoint, _} = reason} ->
        AgentServer.emit_cron_telemetry_event(state, :persist_failure, %{
          job_id: logical_id,
          cron_expression: cron_spec.cron_expression,
          reason: reason
        })

        tracked_state =
          AgentServer.track_cron_job(state, logical_id, new_pid, runtime_spec: runtime_spec)

        committed_state = %{tracked_state | cron_specs: proposed_specs}

        {:ok, committed_state}

      {:error, reason} ->
        Jido.Scheduler.cancel(new_pid)

        AgentServer.emit_cron_telemetry_event(state, :persist_failure, %{
          job_id: logical_id,
          cron_expression: cron_spec.cron_expression,
          reason: reason
        })

        {:error, {:persist_failed, reason}}
    end
  end

  defp handle_failed_registration(state, logical_id, :drop) do
    {_pid, runtime_state} =
      AgentServer.untrack_cron_job(state, logical_id, cancel?: true, drop_runtime_spec?: true)

    %{runtime_state | cron_specs: Map.delete(runtime_state.cron_specs, logical_id)}
  end

  defp handle_failed_registration(state, _logical_id, _on_failure), do: state
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.Cron do
  @moduledoc false

  def exec(
        %{cron: cron_expr, message: message, job_id: logical_id, timezone: tz},
        _input_signal,
        state
      ) do
    Jido.Agent.Directive.Cron.register(
      state,
      cron_expr,
      message,
      logical_id,
      tz,
      on_failure: :keep
    )
  end
end
