defmodule Jido.AgentServer.StopChildRuntime do
  @moduledoc false

  require Logger

  alias Jido.AgentServer.State
  alias Jido.RuntimeStore
  alias Jido.Signal
  alias Jido.Tracing.Context, as: TraceContext

  @relationship_hive :relationships

  @spec exec(term(), term(), Signal.t(), State.t()) :: {:ok, State.t()}
  def exec(tag, reason, %Signal{} = input_signal, %State{} = state) do
    case State.get_child(state, tag) do
      nil ->
        Logger.debug("AgentServer #{state.id} cannot stop child #{inspect(tag)}: not found")
        {:ok, state}

      %{pid: pid, id: child_id, partition: child_partition} ->
        Logger.debug(
          "AgentServer #{state.id} stopping child #{inspect(tag)} with reason #{inspect(reason)}"
        )

        case RuntimeStore.delete(
               state.jido,
               @relationship_hive,
               Jido.partition_key(child_id, child_partition)
             ) do
          :ok ->
            :ok

          {:error, delete_reason} ->
            Logger.warning(
              "AgentServer #{state.id} failed to clear relationship for child #{child_id}: #{inspect(delete_reason)}"
            )
        end

        stop_signal =
          Signal.new!(
            "jido.agent.stop",
            %{reason: normalize_stop_reason(reason)},
            source: "/agent/#{state.id}"
          )

        traced_signal =
          case TraceContext.propagate_to(stop_signal, input_signal.id) do
            {:ok, signal} -> signal
            {:error, _} -> stop_signal
          end

        _ = Jido.AgentServer.cast(pid, traced_signal)

        {:ok, state}
    end
  end

  # Transient children only skip restart for OTP "clean" shutdown reasons.
  # Wrap custom reasons so StopChild removes the child instead of respawning it.
  defp normalize_stop_reason(:normal), do: :normal
  defp normalize_stop_reason(:shutdown), do: :shutdown
  defp normalize_stop_reason({:shutdown, _} = reason), do: reason
  defp normalize_stop_reason(reason), do: {:shutdown, reason}
end
