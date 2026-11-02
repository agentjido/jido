defmodule Jido.Signal.Dispatch.LoggerAdapter do
  @moduledoc """
  Sends a Signal to Elixir Logger.

  The adapter supports plain text and structured map messages. Signal data is
  sanitized before it enters a log message.

  Options:

  - `:level` or `:log_level` sets `:debug`, `:info`, `:warning`, or `:error`.
  - `:structured` selects a map message. The default is plain text.
  - `:include_data` includes sanitized Signal data. The default is `true`.

      Jido.Signal.Dispatch.dispatch(signal, {:logger, level: :info})
  """

  @behaviour Jido.Signal.Dispatch.Adapter

  alias Jido.Signal.Sanitizer

  require Logger

  @valid_levels [:debug, :info, :warning, :error]
  @options_schema Zoi.keyword(
                    [
                      level: Zoi.enum(@valid_levels) |> Zoi.optional(),
                      log_level: Zoi.enum(@valid_levels) |> Zoi.optional(),
                      structured: Zoi.boolean() |> Zoi.optional(),
                      include_data: Zoi.boolean() |> Zoi.optional()
                    ],
                    unrecognized_keys: :error
                  )

  @impl Jido.Signal.Dispatch.Adapter
  def options_schema, do: @options_schema

  @impl Jido.Signal.Dispatch.Adapter
  @doc """
  Logs a signal using the configured format and level.
  """
  @spec deliver(Jido.Signal.t(), Keyword.t()) :: :ok
  def deliver(signal, opts) do
    level = resolve_log_level(opts)
    structured = Keyword.get(opts, :structured, false)
    include_data = Keyword.get(opts, :include_data, true)

    Logger.log(
      level,
      fn ->
        if structured do
          structured_payload(signal, include_data)
        else
          build_log_message(signal, include_data)
        end
      end,
      []
    )

    :ok
  end

  defp structured_payload(signal, include_data) do
    payload = %{
      event: "signal_dispatched",
      id: signal.id,
      type: signal.type,
      source: signal.source
    }

    if include_data do
      Map.put(payload, :data, Sanitizer.sanitize(signal.data, :telemetry))
    else
      payload
    end
  end

  defp build_log_message(signal, false) do
    "SIGNAL: #{signal.type} from #{signal.source}"
  end

  defp build_log_message(signal, true) do
    "SIGNAL: #{signal.type} from #{signal.source} " <>
      "with data=#{Sanitizer.preview(signal.data, :telemetry)}"
  end

  defp resolve_log_level(opts) do
    default =
      :jido
      |> Application.get_env(:default_log_level, :info)
      |> normalize_log_level(:info)

    opts
    |> Keyword.get(:log_level, Keyword.get(opts, :level, default))
    |> normalize_log_level(default)
  end

  defp normalize_log_level(level, _fallback) when level in @valid_levels, do: level
  defp normalize_log_level(_level, fallback), do: fallback
end
