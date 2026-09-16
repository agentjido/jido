defmodule Jido.AgentServer.Admission do
  @moduledoc false

  alias Jido.AgentServer.Turn
  require Logger
  alias Jido.AgentServer.ActiveTurn
  alias Jido.AgentServer.AdmissionDeadline
  alias Jido.AgentServer.State
  alias Jido.Signal
  alias Jido.Telemetry.Agent, as: AgentTelemetry

  def handle_event(
        {:call, from},
        {:signal, token, %Signal{} = signal, deadline, _context},
        phase,
        %State{} = data
      )
      when phase == :initializing do
    postpone_call(from, token, signal, deadline, data)
  end

  def handle_event(
        {:call, from},
        {:signal, token, %Signal{} = signal, deadline, context},
        :idle,
        %State{} = data
      ) do
    data = forget_postponed(data, token)

    if AdmissionDeadline.expired?(deadline) do
      AgentTelemetry.admission_rejected(data, signal, :deadline_expired)
      {:keep_state, data, [{:reply, from, {:error, :admission_timeout}}]}
    else
      Turn.start_turn(signal, from, context, data)
    end
  end

  def handle_event(:cast, {:signal, token, %Signal{} = signal}, :idle, %State{} = data) do
    Turn.start_turn(signal, nil, %{}, forget_postponed(data, token))
  end

  def handle_event(
        {:call, from},
        {:signal, token, %Signal{} = signal, deadline, _context},
        phase,
        %State{} = data
      )
      when phase in [:admitting, :running] do
    reentrant =
      case phase do
        :admitting -> reentrant_task_call?(from, data.admission_task)
        :running -> reentrant_turn_call?(from, data.active)
      end

    if reentrant do
      reason = if phase == :admitting, do: :reentrant_admission, else: :reentrant_turn
      {:keep_state_and_data, [{:reply, from, {:error, reason}}]}
    else
      postpone_call(from, token, signal, deadline, data)
    end
  end

  def handle_event(
        {:call, from},
        {:signal, token, %Signal{} = signal, deadline, _context},
        :directing,
        %State{} = data
      ) do
    cond do
      reentrant_task_call?(from, data.commit_task) ->
        {:keep_state_and_data, [{:reply, from, {:error, :reentrant_commit}}]}

      reentrant_task_call?(from, data.directive_task) ->
        {:keep_state_and_data, [{:reply, from, {:error, :reentrant_directive}}]}

      true ->
        postpone_call(from, token, signal, deadline, data)
    end
  end

  def handle_event(:cast, {:signal, token, %Signal{} = signal}, phase, %State{} = data)
      when phase in [:initializing, :admitting, :running, :directing] do
    postpone_cast(token, signal, data)
  end

  defp postpone_call(from, token, signal, deadline, %State{} = data) do
    cond do
      AdmissionDeadline.expired?(deadline) ->
        AgentTelemetry.admission_rejected(data, signal, :deadline_expired)

        {:keep_state, forget_postponed(data, token),
         [{:reply, from, {:error, :admission_timeout}}]}

      MapSet.member?(data.postponed_tokens, token) ->
        {:keep_state_and_data, [:postpone]}

      admission_full?(data) ->
        AgentTelemetry.admission_rejected(data, signal, :overloaded)
        {:keep_state_and_data, [{:reply, from, {:error, overload_error(data)}}]}

      true ->
        {:keep_state, remember_postponed(data, token), [:postpone]}
    end
  end

  defp postpone_cast(token, signal, %State{} = data) do
    cond do
      MapSet.member?(data.postponed_tokens, token) ->
        {:keep_state_and_data, [:postpone]}

      admission_full?(data) ->
        AgentTelemetry.admission_rejected(data, signal, :overloaded)

        Logger.warning("Agent Signal cast dropped because the Server is overloaded",
          agent_id: data.agent.id,
          signal_id: signal.id,
          signal_type: signal.type
        )

        :keep_state_and_data

      true ->
        {:keep_state, remember_postponed(data, token), [:postpone]}
    end
  end

  defp remember_postponed(%State{} = data, token) do
    %{data | postponed_tokens: MapSet.put(data.postponed_tokens, token)}
  end

  defp forget_postponed(%State{} = data, token) do
    %{data | postponed_tokens: MapSet.delete(data.postponed_tokens, token)}
  end

  defp admission_full?(%State{max_postponed_signals: :infinity}), do: false

  defp admission_full?(%State{} = data) do
    MapSet.size(data.postponed_tokens) >= data.max_postponed_signals
  end

  defp overload_error(%State{} = data) do
    {:overloaded,
     %{limit: data.max_postponed_signals, postponed: MapSet.size(data.postponed_tokens)}}
  end

  defp reentrant_turn_call?({caller, _tag}, %ActiveTurn{exec_handle: %{pid: root}})
       when is_pid(caller) and is_pid(root) do
    related_exec_process?(caller, root, %{}, 0)
  end

  defp reentrant_turn_call?(_from, _active), do: false

  defp reentrant_task_call?({caller, _tag}, %{task: %Task{pid: root}})
       when is_pid(caller) and is_pid(root) do
    related_exec_process?(caller, root, %{}, 0)
  end

  defp reentrant_task_call?(_from, _pending_task), do: false
  defp related_exec_process?(pid, root, _visited, _depth) when pid == root, do: true
  defp related_exec_process?(_pid, _root, _visited, depth) when depth >= 8, do: false

  defp related_exec_process?(pid, root, visited, depth) do
    if Map.has_key?(visited, pid) do
      false
    else
      visited = Map.put(visited, pid, true)

      pid
      |> exec_process_parents()
      |> Enum.any?(&related_exec_process?(&1, root, visited, depth + 1))
    end
  end

  defp exec_process_parents(pid) when node(pid) != node(), do: []

  defp exec_process_parents(pid) do
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
