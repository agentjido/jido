defmodule Jido.Agent.Schedules do
  @moduledoc """
  Utilities for expanding agent-level schedule declarations.

  Agent schedules are declared in `use Jido.Agent, schedules: [...]` and
  target signal types that get routed through `signal_routes/1`.

  ## Schedule Formats

  - `{"* * * * *", "signal.type"}` - Cron expression + signal type
  - `{"* * * * *", "signal.type", job_id: :my_job}` - With explicit job ID
  - `{"* * * * *", "signal.type", job_id: :my_job, timezone: "America/New_York"}` - With timezone

  ## Job ID Namespacing

  Job IDs are namespaced as tuples: `{:agent_schedule, agent_name, signal_type_or_job_id}`
  """

  @typedoc "Expanded agent schedule specification (same shape as plugin schedule specs)."
  @type schedule_spec :: %{
          cron_expression: String.t(),
          action: nil,
          job_id: {:agent_schedule, String.t(), term()},
          signal_type: String.t(),
          timezone: String.t()
        }

  @doc """
  Expands agent schedule declarations into schedule specs.

  ## Examples

      iex> expand_schedules([{"* * * * *", "heartbeat.tick", job_id: :hb}], "my_agent")
      [%{cron_expression: "* * * * *", action: nil, job_id: {:agent_schedule, "my_agent", :hb}, signal_type: "heartbeat.tick", timezone: "Etc/UTC"}]
  """
  @spec expand_schedules(list(), String.t()) :: [schedule_spec()]
  def expand_schedules(schedules, agent_name) when is_list(schedules) do
    Enum.map(schedules, fn schedule ->
      expand_schedule(schedule, agent_name)
    end)
  end

  @doc """
  Returns an empty list of routes for agent schedule signal types.

  Agent schedules target signal types (not action modules directly),
  so the user must define matching routes in `signal_routes/1`.
  No automatic routes are generated.
  """
  @spec schedule_routes([schedule_spec()]) :: []
  def schedule_routes(_schedules), do: []

  defp expand_schedule({cron_expr, signal_type}, agent_name) do
    expand_schedule({cron_expr, signal_type, []}, agent_name)
  end

  defp expand_schedule({cron_expr, signal_type, opts}, agent_name)
       when is_binary(cron_expr) and is_binary(signal_type) and is_list(opts) do
    timezone = Keyword.get(opts, :timezone, "Etc/UTC")
    job_id_value = Keyword.get(opts, :job_id, signal_type)
    job_id = {:agent_schedule, agent_name, job_id_value}

    %{
      cron_expression: cron_expr,
      action: nil,
      job_id: job_id,
      signal_type: signal_type,
      timezone: timezone
    }
  end
end
