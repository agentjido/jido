defmodule Jido.AgentServer.CronRuntimeSpec do
  @moduledoc false

  alias Jido.AgentServer.Signal.CronTick
  alias Jido.Signal

  @default_timezone "Etc/UTC"

  @enforce_keys [:kind, :cron_expression, :timezone]
  defstruct [:kind, :cron_expression, :timezone, :message, :signal_type]

  @type kind :: :dynamic | :schedule

  @type t ::
          %__MODULE__{
            kind: kind(),
            cron_expression: String.t(),
            timezone: String.t(),
            message: term() | nil,
            signal_type: String.t() | nil
          }

  @spec dynamic(String.t(), term(), String.t() | nil) :: t()
  def dynamic(cron_expression, message, timezone \\ nil) when is_binary(cron_expression) do
    %__MODULE__{
      kind: :dynamic,
      cron_expression: cron_expression,
      timezone: normalize_timezone(timezone),
      message: message
    }
  end

  @spec schedule(String.t(), String.t(), String.t() | nil) :: t()
  def schedule(cron_expression, signal_type, timezone \\ nil)
      when is_binary(cron_expression) and is_binary(signal_type) do
    %__MODULE__{
      kind: :schedule,
      cron_expression: cron_expression,
      timezone: normalize_timezone(timezone),
      signal_type: signal_type
    }
  end

  @spec build_signal(t(), String.t(), term()) :: Jido.Signal.t()
  def build_signal(
        %__MODULE__{kind: :dynamic, message: %Signal{} = signal},
        _agent_id,
        _logical_id
      ),
      do: signal

  def build_signal(%__MODULE__{kind: :dynamic, message: message}, agent_id, logical_id) do
    CronTick.new!(
      %{job_id: logical_id, message: message},
      source: "/agent/#{agent_id}"
    )
  end

  def build_signal(%__MODULE__{kind: :schedule, signal_type: signal_type}, agent_id, _logical_id) do
    Signal.new!(signal_type, %{}, source: "/agent/#{agent_id}/schedule")
  end

  defp normalize_timezone(nil), do: @default_timezone
  defp normalize_timezone(""), do: @default_timezone
  defp normalize_timezone(timezone), do: timezone
end
