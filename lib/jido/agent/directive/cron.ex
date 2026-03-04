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
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.Cron do
  @moduledoc false

  require Logger

  alias Jido.AgentServer
  alias Jido.AgentServer.Signal.CronTick

  def exec(
        %{cron: cron_expr, message: message, job_id: logical_id, timezone: tz},
        _input_signal,
        state
      ) do
    agent_id = state.id
    logical_id = logical_id || make_ref()

    with :ok <- validate_registration_input(cron_expr, tz),
         {:ok, pid} <- start_runtime_job(state, cron_expr, message, logical_id, tz),
         {:ok, persisted_state} <-
           persist_then_commit_registration(state, pid, logical_id, cron_expr, message, tz) do
      Logger.debug(
        "AgentServer #{agent_id} registered cron job #{inspect(logical_id)}: #{cron_expr}"
      )

      AgentServer.emit_cron_telemetry_event(persisted_state, :register, %{
        job_id: logical_id,
        cron_expression: cron_expr
      })

      {:ok, persisted_state}
    else
      {:error, reason} ->
        Logger.error(
          "AgentServer #{agent_id} failed to register cron job #{inspect(logical_id)}: #{inspect(reason)}"
        )

        {:ok, state}
    end
  end

  defp build_signal(%Jido.Signal{} = signal, _logical_id, _agent_id), do: signal

  defp build_signal(message, logical_id, agent_id) do
    CronTick.new!(
      %{job_id: logical_id, message: message},
      source: "/agent/#{agent_id}"
    )
  end

  defp start_runtime_job(state, cron_expr, message, logical_id, tz) do
    agent_pid = self()
    signal = build_signal(message, logical_id, state.id)
    opts = if is_binary(tz), do: [timezone: tz], else: []

    Jido.Scheduler.run_every(
      fn ->
        if Process.alive?(agent_pid) do
          _ = Jido.AgentServer.cast(agent_pid, signal)
        end

        :ok
      end,
      cron_expr,
      opts
    )
  end

  defp persist_then_commit_registration(state, new_pid, logical_id, cron_expr, message, tz) do
    cron_spec = Jido.Scheduler.build_cron_spec(cron_expr, message, tz)
    proposed_specs = Map.put(state.cron_specs, logical_id, cron_spec)

    case AgentServer.persist_cron_specs(state, proposed_specs) do
      :ok ->
        tracked_state = AgentServer.track_cron_job(state, logical_id, new_pid)
        committed_state = %{tracked_state | cron_specs: proposed_specs}

        {:ok, committed_state}

      {:error, reason} ->
        Jido.Scheduler.cancel(new_pid)

        AgentServer.emit_cron_telemetry_event(state, :persist_failure, %{
          job_id: logical_id,
          cron_expression: cron_expr,
          reason: reason
        })

        {:error, {:persist_failed, reason}}
    end
  end

  defp validate_registration_input(cron_expr, _tz) when not is_binary(cron_expr),
    do: {:error, :invalid_cron_expression}

  defp validate_registration_input(_cron_expr, tz) when not (is_nil(tz) or is_binary(tz)),
    do: {:error, :invalid_timezone}

  defp validate_registration_input(_cron_expr, _tz) do
    :ok
  end
end
