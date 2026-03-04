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

  alias Jido.AgentServer.Signal.CronTick

  def exec(
        %{cron: cron_expr, message: message, job_id: logical_id, timezone: tz},
        _input_signal,
        state
      ) do
    agent_id = state.id
    # Capture the AgentServer PID at registration time so cron ticks
    # route back to this process. Using the string `agent_id` would fail
    # because `resolve_server/1` rejects binary IDs. (See issue #136)
    agent_pid = self()
    logical_id = logical_id || make_ref()
    signal = build_signal(message, logical_id, agent_id)

    state = cancel_existing_job(state, logical_id)

    opts = build_scheduler_opts(tz)

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
    |> handle_scheduler_result(state, agent_id, logical_id, cron_expr, message, tz)
  end

  defp build_signal(%Jido.Signal{} = signal, _logical_id, _agent_id), do: signal

  defp build_signal(message, logical_id, agent_id) do
    CronTick.new!(
      %{job_id: logical_id, message: message},
      source: "/agent/#{agent_id}"
    )
  end

  defp cancel_existing_job(state, logical_id) do
    case Map.get(state.cron_jobs, logical_id) do
      pid when is_pid(pid) -> Jido.Scheduler.cancel(pid)
      _ -> :ok
    end

    %{
      state
      | cron_jobs: Map.delete(state.cron_jobs, logical_id),
        cron_specs: Map.delete(state.cron_specs, logical_id)
    }
  end

  defp build_scheduler_opts(nil), do: []
  defp build_scheduler_opts(tz), do: [timezone: tz]

  defp handle_scheduler_result(
         {:ok, pid},
         state,
         agent_id,
         logical_id,
         cron_expr,
         message,
         tz
       ) do
    Logger.debug(
      "AgentServer #{agent_id} registered cron job #{inspect(logical_id)}: #{cron_expr}"
    )

    cron_spec = Jido.Scheduler.build_cron_spec(cron_expr, message, tz)

    new_state = %{
      state
      | cron_jobs: Map.put(state.cron_jobs, logical_id, pid),
        cron_specs: Map.put(state.cron_specs, logical_id, cron_spec)
    }

    {:ok, new_state}
  end

  defp handle_scheduler_result(
         {:error, reason},
         _state,
         agent_id,
         logical_id,
         _cron_expr,
         _message,
         _tz
       ) do
    Logger.error(
      "AgentServer #{agent_id} failed to register cron job #{inspect(logical_id)}: #{inspect(reason)}"
    )

    {:error, reason}
  end
end
