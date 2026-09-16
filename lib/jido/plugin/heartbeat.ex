defmodule Jido.Plugin.Heartbeat do
  @moduledoc """
  Sends a periodic Signal to its Agent.

  This is a small example of an input Plugin. The Plugin runtime owns the
  timer. Each tick enters the Agent through its normal Signal mailbox.

  The default message uses `Jido.Plugin.Heartbeat.Signal.Tick`. Set
  `:signal_type` to send an application-defined Signal type instead.

      plugins: [
        {Jido.Plugin.Heartbeat,
         interval: 1_000,
         signal_type: "system.heartbeat",
         signal_data: %{source: :clock}}
      ]
  """

  use Jido.Plugin, agent_server: Jido.Plugin.Heartbeat.Server

  alias Jido.Plugin.Heartbeat.Signal.Tick
  alias Jido.Signal

  @default_interval 5_000

  @doc false
  def configuration(opts) when is_list(opts) do
    config = %{
      interval: Keyword.get(opts, :interval, @default_interval),
      signal_type: Keyword.get(opts, :signal_type, Tick.type()),
      signal_data: Keyword.get(opts, :signal_data, %{}),
      source: Keyword.get(opts, :source, Tick.default_source())
    }

    with :ok <- validate_interval(config.interval),
         :ok <- validate_signal_type(config.signal_type),
         :ok <- validate_signal_data(config.signal_data),
         :ok <- validate_source(config.source) do
      {:ok, config}
    end
  end

  def configuration(opts), do: {:error, {:invalid_heartbeat_options, opts}}

  defp validate_interval(interval) when is_integer(interval) and interval > 0, do: :ok
  defp validate_interval(interval), do: {:error, {:invalid_heartbeat_interval, interval}}

  defp validate_signal_type(type) when is_binary(type) and type != "" do
    case Signal.validate_utf8_string(type, []) do
      :ok -> :ok
      _error -> {:error, {:invalid_heartbeat_signal_type, type}}
    end
  end

  defp validate_signal_type(type), do: {:error, {:invalid_heartbeat_signal_type, type}}

  defp validate_signal_data(data) when is_map(data) and not is_struct(data), do: :ok
  defp validate_signal_data(data), do: {:error, {:invalid_heartbeat_signal_data, data}}

  defp validate_source(source) when is_binary(source) and source != "" do
    case Signal.validate_uri_reference(source, []) do
      :ok -> :ok
      _error -> {:error, {:invalid_heartbeat_source, source}}
    end
  end

  defp validate_source(source), do: {:error, {:invalid_heartbeat_source, source}}
end
