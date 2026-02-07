defmodule Jido.Plugin.Schedules do
  @moduledoc """
  Utilities for expanding and managing plugin schedules.

  This module handles:
  - Expanding schedule declarations from plugin manifests
  - Generating unique job IDs namespaced to plugin instances
  - Generating signal types for schedule triggers
  - Managing timezone configuration

  ## Schedule Formats

  Schedules can be specified in several formats:

  - `{"*/5 * * * *", ActionModule}` - Simple schedule with default timezone
  - `{"*/5 * * * *", ActionModule, tz: "America/New_York"}` - With timezone
  - `{"*/5 * * * *", ActionModule, signal: "custom.signal"}` - Custom signal type

  ## Signal Type Generation

  By default, schedule signal types are auto-generated as:
  `"{route_prefix}.__schedule__.{action_name}"`

  For example, a plugin with route_prefix "slack" and action RefreshToken
  would generate signal type "slack.__schedule__.refresh_token".

  Custom signal types can be specified with the `:signal` option.

  ## Job ID Namespacing

  Job IDs are namespaced as tuples to ensure uniqueness across plugin instances:
  `{:plugin_schedule, state_key, ActionModule}`
  """

  alias Jido.Plugin.Instance

  @schedule_route_priority -20

  @typedoc """
  Represents an expanded schedule specification.
  """
  @type schedule_spec :: %{
          cron_expression: String.t(),
          action: module(),
          job_id: {:plugin_schedule, atom(), module()},
          signal_type: String.t(),
          timezone: String.t()
        }

  @doc """
  Expands schedules from a plugin instance.

  Takes a plugin instance and returns expanded schedule specifications
  with unique job IDs and auto-generated signal types.

  ## Input Formats

  - `{"*/5 * * * *", ActionModule}` - Simple with default timezone
  - `{"*/5 * * * *", ActionModule, tz: "America/New_York"}` - With timezone
  - `{"*/5 * * * *", ActionModule, signal: "custom.signal"}` - Custom signal

  ## Examples

      iex> instance = Instance.new(SlackPlugin)  # route_prefix: "slack"
      iex> expand_schedules(instance)
      [
        %{
          cron_expression: "*/5 * * * *",
          action: SlackActions.RefreshToken,
          job_id: {:plugin_schedule, :slack, SlackActions.RefreshToken},
          signal_type: "slack.__schedule__.refresh_token",
          timezone: "Etc/UTC"
        }
      ]

      iex> instance = Instance.new({SlackPlugin, as: :support})
      iex> expand_schedules(instance)
      [
        %{
          cron_expression: "*/5 * * * *",
          action: SlackActions.RefreshToken,
          job_id: {:plugin_schedule, :slack_support, SlackActions.RefreshToken},
          signal_type: "support.slack.__schedule__.refresh_token",
          timezone: "Etc/UTC"
        }
      ]
  """
  @spec expand_schedules(Instance.t()) :: [schedule_spec()]
  def expand_schedules(%Instance{} = instance) do
    manifest = instance.manifest
    schedules = manifest.schedules || []
    state_key = instance.state_key
    route_prefix = instance.route_prefix

    Enum.map(schedules, fn schedule ->
      expand_schedule(schedule, state_key, route_prefix)
    end)
  end

  @doc """
  Generates routes for schedule signal types.

  Schedule signal types need routes so they can be dispatched through
  the normal signal routing pipeline. These routes have low priority
  to avoid conflicting with explicit routes.

  Returns a list of route tuples suitable for `Routes.detect_conflicts/1`.
  """
  @spec schedule_routes(Instance.t()) :: [{String.t(), module(), keyword()}]
  def schedule_routes(%Instance{} = instance) do
    instance
    |> expand_schedules()
    |> Enum.map(fn spec ->
      {spec.signal_type, spec.action, [priority: @schedule_route_priority]}
    end)
  end

  @doc """
  Returns the default priority for schedule-generated routes.
  """
  @spec schedule_route_priority() :: integer()
  def schedule_route_priority, do: @schedule_route_priority

  defp expand_schedule({cron_expr, action}, state_key, route_prefix) do
    expand_schedule({cron_expr, action, []}, state_key, route_prefix)
  end

  defp expand_schedule({cron_expr, action, opts}, state_key, route_prefix)
       when is_list(opts) do
    timezone = Keyword.get(opts, :tz, "Etc/UTC")
    custom_signal = Keyword.get(opts, :signal)

    signal_type =
      if custom_signal do
        "#{route_prefix}.#{custom_signal}"
      else
        generate_signal_type(route_prefix, action)
      end

    job_id = {:plugin_schedule, state_key, action}

    %{
      cron_expression: cron_expr,
      action: action,
      job_id: job_id,
      signal_type: signal_type,
      timezone: timezone
    }
  end

  defp generate_signal_type(route_prefix, action) do
    action_name =
      action
      |> Module.split()
      |> List.last()
      |> Macro.underscore()

    "#{route_prefix}.__schedule__.#{action_name}"
  end
end
