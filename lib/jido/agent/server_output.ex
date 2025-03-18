defmodule Jido.Agent.Server.Output do
  @moduledoc false
  use ExDbug, enabled: false
  alias Jido.Signal
  alias Jido.Signal.Dispatch
  alias Jido.Agent.Server.State, as: ServerState

  @type log_levels ::
          :debug | :info | :notice | :warning | :error | :critical | :alert | :emergency
  @default_dispatch {:logger, [level: :info]}

  def log(level_or_state, message, opts \\ [])

  def log(%ServerState{log_level: log_level, agent: %{id: agent_id}} = _state, message, opts) do
    opts = Keyword.merge(opts, agent_id: agent_id)
    do_log(log_level, message, opts)
  end

  def log(log_level, message, opts) when is_atom(log_level) do
    do_log(log_level, message, opts)
  end

  defp do_log(log_level, message, opts) do
    original_level = Logger.level()

    try do
      Logger.configure(level: log_level)

      metadata =
        opts
        |> Enum.map_join(" ", fn {k, v} -> "#{k}=#{v}" end)

      message = if metadata != "", do: "#{message} #{metadata}", else: message

      case log_level do
        :debug -> Logger.debug(message)
        :info -> Logger.info(message)
        :notice -> Logger.notice(message)
        :warning -> Logger.warning(message)
        :error -> Logger.error(message)
        :critical -> Logger.critical(message)
        :alert -> Logger.alert(message)
        :emergency -> Logger.emergency(message)
        _ -> Logger.info(message)
      end
    after
      Logger.configure(level: original_level)
    end
  end

  def emit(signal, opts \\ [])

  def emit(nil, _opts) do
    dbug("No signal provided")
    {:error, :no_signal}
  end

  def emit(%Signal{} = signal, opts) do
    dispatch_config =
      Keyword.get(opts, :dispatch) || signal.jido_dispatch || @default_dispatch

    dbug("Emitting", signal: signal, opts: opts)
    dbug("Using dispatch config", dispatch_config: dispatch_config)

    Dispatch.dispatch(signal, dispatch_config)
  end

  def emit(_invalid, _opts) do
    {:error, :invalid_signal}
  end
end
