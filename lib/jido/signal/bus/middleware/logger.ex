defmodule Jido.Signal.Bus.Middleware.Logger do
  @moduledoc """
  A middleware that logs signal activity using Elixir's Logger.

  This middleware provides comprehensive logging of signal flows through the bus,
  including publishing events, dispatch events, and errors. It's useful for
  debugging, monitoring, and auditing signal activity.

  ## Configuration Options

  - `:level` - Log level to use (default: `:info`)
  - `:log_publish` - Whether to log publish events (default: `true`)
  - `:log_dispatch` - Whether to log dispatch events (default: `true`)
  - `:log_errors` - Whether to log errors (default: `true`)
  - `:include_signal_data` - Whether to include signal data in logs (default: `false`)
  - `:max_data_length` - Maximum length of signal data to log (default: `100`)

  ## Examples

      # Basic logging at info level
      middleware = [{Jido.Signal.Bus.Middleware.Logger, []}]

      # Debug level with signal data
      middleware = [
        {Jido.Signal.Bus.Middleware.Logger, [
          level: :debug,
          include_signal_data: true,
          max_data_length: 200
        ]}
      ]

      # Only log errors
      middleware = [
        {Jido.Signal.Bus.Middleware.Logger, [
          log_publish: false,
          log_dispatch: false,
          log_errors: true
        ]}
      ]
  """

  use Jido.Signal.Bus.Middleware

  require Logger

  @impl true
  def init(opts) do
    config = %{
      level: Keyword.get(opts, :level, :info),
      log_publish: Keyword.get(opts, :log_publish, true),
      log_dispatch: Keyword.get(opts, :log_dispatch, true),
      log_errors: Keyword.get(opts, :log_errors, true),
      include_signal_data: Keyword.get(opts, :include_signal_data, false),
      max_data_length: Keyword.get(opts, :max_data_length, 100)
    }

    {:ok, config}
  end

  @impl true
  def before_publish(signals, context, config) do
    if config.log_publish do
      signal_count = length(signals)
      signal_types = signals |> Enum.map(& &1.type) |> Enum.uniq()

      Logger.log(
        config.level,
        "Bus #{context.bus_name}: Publishing #{signal_count} signal(s) of types: #{inspect(signal_types)}",
        bus_name: context.bus_name,
        signal_count: signal_count,
        signal_types: signal_types,
        timestamp: context.timestamp
      )

      if config.include_signal_data do
        Enum.each(signals, fn signal ->
          data_preview = format_signal_data(signal.data, config.max_data_length)

          Logger.log(
            config.level,
            "Signal #{signal.id} (#{signal.type}): #{data_preview}",
            signal_id: signal.id,
            signal_type: signal.type,
            signal_source: signal.source,
            signal_data: data_preview
          )
        end)
      end
    end

    {:cont, signals, config}
  end

  @impl true
  def after_publish(signals, context, config) do
    if config.log_publish do
      signal_count = length(signals)

      Logger.log(
        config.level,
        "Bus #{context.bus_name}: Successfully published #{signal_count} signal(s)",
        bus_name: context.bus_name,
        signal_count: signal_count,
        timestamp: context.timestamp
      )
    end

    {:cont, signals, config}
  end

  @impl true
  def before_dispatch(signal, subscriber, context, config) do
    if config.log_dispatch do
      dispatch_info = format_dispatch_info(subscriber.dispatch)

      Logger.log(
        config.level,
        "Bus #{context.bus_name}: Dispatching signal #{signal.id} (#{signal.type}) to #{dispatch_info}",
        bus_name: context.bus_name,
        signal_id: signal.id,
        signal_type: signal.type,
        subscriber_path: subscriber.path,
        dispatch_target: dispatch_info,
        timestamp: context.timestamp
      )
    end

    {:cont, signal, config}
  end

  @impl true
  def after_dispatch(signal, subscriber, result, context, config) do
    case result do
      :ok ->
        if config.log_dispatch do
          dispatch_info = format_dispatch_info(subscriber.dispatch)

          Logger.log(
            config.level,
            "Bus #{context.bus_name}: Successfully dispatched signal #{signal.id} to #{dispatch_info}",
            bus_name: context.bus_name,
            signal_id: signal.id,
            signal_type: signal.type,
            subscriber_path: subscriber.path,
            dispatch_target: dispatch_info,
            result: :success,
            timestamp: context.timestamp
          )
        end

      {:error, reason} ->
        if config.log_errors do
          dispatch_info = format_dispatch_info(subscriber.dispatch)

          Logger.log(
            :error,
            "Bus #{context.bus_name}: Failed to dispatch signal #{signal.id} to #{dispatch_info}: #{inspect(reason)}",
            bus_name: context.bus_name,
            signal_id: signal.id,
            signal_type: signal.type,
            subscriber_path: subscriber.path,
            dispatch_target: dispatch_info,
            result: :error,
            error_reason: reason,
            timestamp: context.timestamp
          )
        end
    end

    {:cont, config}
  end

  # Private helper functions

  defp format_signal_data(nil, _max_length), do: "nil"

  defp format_signal_data(data, max_length) when is_binary(data) do
    if String.length(data) > max_length do
      String.slice(data, 0, max_length) <> "..."
    else
      data
    end
  end

  defp format_signal_data(data, max_length) do
    formatted = inspect(data, limit: :infinity, printable_limit: :infinity)

    if String.length(formatted) > max_length do
      String.slice(formatted, 0, max_length) <> "..."
    else
      formatted
    end
  end

  defp format_dispatch_info({:pid, opts}) do
    target = Keyword.get(opts, :target, "unknown")
    mode = Keyword.get(opts, :delivery_mode, :async)
    "pid(#{inspect(target)}, #{mode})"
  end

  defp format_dispatch_info({:function, {module, function}}) do
    "function(#{module}.#{function})"
  end

  defp format_dispatch_info({:function, {module, function, args}}) do
    "function(#{module}.#{function}/#{length(args)})"
  end

  defp format_dispatch_info(dispatch) do
    inspect(dispatch)
  end
end
