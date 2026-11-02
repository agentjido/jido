defmodule Jido.Signal.Dispatch.PidAdapter do
  @moduledoc """
  Delivers a Signal to a local process.

  The `:pid` and `:named` dispatch inputs use this adapter. A target is a PID
  or `{:name, registered_name}`. Async delivery sends a message. Sync delivery
  uses `GenServer.call/3`.
  """

  @behaviour Jido.Signal.Dispatch.Adapter

  @target_schema Zoi.union([
                   Zoi.pid(),
                   Zoi.tuple({Zoi.literal(:name), Zoi.atom()})
                 ])
                 |> Zoi.refine({__MODULE__, :validate_target, []})

  @options_schema Zoi.keyword(
                    [
                      target: @target_schema |> Zoi.required(),
                      delivery_mode: Zoi.enum([:sync, :async]) |> Zoi.default(:async),
                      timeout:
                        Zoi.integer()
                        |> Zoi.min(1)
                        |> Zoi.max(4_294_967_295)
                        |> Zoi.default(5_000),
                      message_format: Zoi.function(arity: 1) |> Zoi.optional()
                    ],
                    unrecognized_keys: :error
                  )

  @type delivery_target :: pid() | {:name, atom()}
  @type delivery_mode :: :sync | :async
  @type message_format :: (Jido.Signal.t() -> term())
  @type delivery_opts :: [
          target: delivery_target(),
          delivery_mode: delivery_mode(),
          timeout: 1..4_294_967_295,
          message_format: message_format()
        ]

  @impl Jido.Signal.Dispatch.Adapter
  def options_schema, do: @options_schema

  @impl Jido.Signal.Dispatch.Adapter
  @spec deliver(Jido.Signal.t(), delivery_opts()) :: :ok | {:error, term()}
  def deliver(signal, opts) do
    with {:ok, pid} <- resolve_target(Keyword.fetch!(opts, :target)) do
      deliver_to_process(
        pid,
        Keyword.fetch!(opts, :delivery_mode),
        Keyword.fetch!(opts, :timeout),
        format_message(signal, opts)
      )
    end
  end

  @doc false
  def validate_target({:name, nil}, _opts), do: {:error, "registered name must not be nil"}

  def validate_target(target, _opts) when is_pid(target) and node(target) != node(),
    do: {:error, "target must be a local PID"}

  def validate_target(_target, _opts), do: :ok

  defp resolve_target(pid) when is_pid(pid) do
    if Process.alive?(pid), do: {:ok, pid}, else: {:error, :process_not_alive}
  end

  defp resolve_target({:name, name}) do
    case Process.whereis(name) do
      nil -> {:error, :process_not_found}
      pid -> resolve_target(pid)
    end
  end

  defp deliver_to_process(pid, :async, _timeout, message) do
    send(pid, message)
    :ok
  end

  defp deliver_to_process(pid, :sync, timeout, message) when pid == self() do
    {:error, {:calling_self, {GenServer, :call, [pid, message, timeout]}}}
  end

  defp deliver_to_process(pid, :sync, timeout, message) do
    case GenServer.call(pid, message, timeout) do
      {:error, _reason} = error -> error
      _successful_reply -> :ok
    end
  catch
    :exit, {:timeout, _details} -> {:error, :timeout}
    :exit, {:noproc, _details} -> {:error, :process_not_alive}
    :exit, reason -> {:error, reason}
  end

  defp format_message(signal, opts) do
    opts
    |> Keyword.get(:message_format, &default_message_format/1)
    |> then(& &1.(signal))
  end

  defp default_message_format(signal), do: {:signal, signal}
end
