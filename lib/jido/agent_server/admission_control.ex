defmodule Jido.AgentServer.AdmissionControl do
  @moduledoc false

  require Logger

  alias Jido.AgentServer.{ActiveTurn, AdmissionDeadline, ExecutionAdapter, State}
  alias Jido.Telemetry.Agent, as: AgentTelemetry

  @doc false
  def postpone_call(from, token, signal, deadline, %State{} = data) do
    cond do
      AdmissionDeadline.expired?(deadline) ->
        AgentTelemetry.admission_rejected(data, signal, :deadline_expired)

        {:keep_state, forget(data, token), [{:reply, from, {:error, :admission_timeout}}]}

      MapSet.member?(data.postponed_tokens, token) ->
        {:keep_state_and_data, [:postpone]}

      full?(data) ->
        AgentTelemetry.admission_rejected(data, signal, :overloaded)
        {:keep_state_and_data, [{:reply, from, {:error, overload_error(data)}}]}

      true ->
        {:keep_state, remember(data, token), [:postpone]}
    end
  end

  @doc false
  def postpone_cast(token, signal, %State{} = data) do
    cond do
      MapSet.member?(data.postponed_tokens, token) ->
        {:keep_state_and_data, [:postpone]}

      full?(data) ->
        AgentTelemetry.admission_rejected(data, signal, :overloaded)

        Logger.warning("Agent Signal cast dropped because the Server is overloaded",
          agent_id: data.agent.id,
          signal_id: signal.id,
          signal_type: signal.type
        )

        :keep_state_and_data

      true ->
        {:keep_state, remember(data, token), [:postpone]}
    end
  end

  @doc false
  def forget(%State{} = data, token) do
    %{data | postponed_tokens: MapSet.delete(data.postponed_tokens, token)}
  end

  @doc false
  def reentrant_turn_call?(
        {caller, _tag},
        %ActiveTurn{exec_handle: %ExecutionAdapter{exec_pid: root}}
      )
      when is_pid(caller) and is_pid(root) do
    related_process?(caller, root, %{}, 0)
  end

  def reentrant_turn_call?({caller, _tag}, %ActiveTurn{exec_handle: %{pid: root}})
      when is_pid(caller) and is_pid(root) do
    related_process?(caller, root, %{}, 0)
  end

  def reentrant_turn_call?(_from, _active), do: false

  @doc false
  def reentrant_task_call?({caller, _tag}, %{task: %Task{pid: root}})
      when is_pid(caller) and is_pid(root) do
    related_process?(caller, root, %{}, 0)
  end

  def reentrant_task_call?(_from, _task), do: false

  defp remember(%State{} = data, token) do
    %{data | postponed_tokens: MapSet.put(data.postponed_tokens, token)}
  end

  defp full?(%State{max_postponed_signals: :infinity}), do: false

  defp full?(%State{} = data) do
    MapSet.size(data.postponed_tokens) >= data.max_postponed_signals
  end

  defp overload_error(%State{} = data) do
    {:overloaded,
     %{limit: data.max_postponed_signals, postponed: MapSet.size(data.postponed_tokens)}}
  end

  defp related_process?(pid, root, _visited, _depth) when pid == root, do: true
  defp related_process?(_pid, _root, _visited, depth) when depth >= 8, do: false

  defp related_process?(pid, root, visited, depth) do
    if Map.has_key?(visited, pid) do
      false
    else
      visited = Map.put(visited, pid, true)

      pid
      |> process_parents()
      |> Enum.any?(&related_process?(&1, root, visited, depth + 1))
    end
  end

  defp process_parents(pid) when node(pid) != node(), do: []

  defp process_parents(pid) do
    monitored_by =
      case Process.info(pid, :monitored_by) do
        {:monitored_by, pids} -> pids
        nil -> []
      end

    callers =
      case Process.info(pid, :dictionary) do
        {:dictionary, dictionary} ->
          dictionary
          |> Keyword.get(:"$callers", [])
          |> List.wrap()

        nil ->
          []
      end

    (monitored_by ++ callers)
    |> Enum.filter(&is_pid/1)
    |> Enum.uniq()
  end
end
