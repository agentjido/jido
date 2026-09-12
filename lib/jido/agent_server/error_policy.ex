defmodule Jido.AgentServer.ErrorPolicy do
  @moduledoc false

  require Logger

  alias Jido.Agent.Turn.Outcome
  alias Jido.AgentServer.{Debug, DirectiveRuntime, State}
  alias Jido.Error
  alias Jido.Signal
  alias Jido.Tracing.Context, as: TraceContext

  @dispatch_fallback_timeout 5_000
  @max_tasks 32

  @doc false
  @spec decision(Outcome.t(), State.t()) ::
          {:continue, State.t()} | {:stop, term(), State.t()}
  def decision(%Outcome{}, %State{error_policy: :log_only} = data),
    do: {:continue, data}

  def decision(%Outcome{} = outcome, %State{error_policy: :stop_on_error} = data),
    do: {:stop, {:agent_error, outcome.error}, data}

  def decision(%Outcome{} = outcome, %State{error_policy: {:max_errors, max}} = data) do
    if data.error_count >= max,
      do: {:stop, {:max_agent_errors, outcome.error}, data},
      else: {:continue, data}
  end

  def decision(%Outcome{} = outcome, %State{error_policy: {:emit_signal, dispatch}} = data) do
    source_signal = outcome.effective_signal || outcome.source_signal

    if source_signal.type == "jido.agent.error" do
      {:continue, data}
    else
      signal =
        Signal.new!(
          type: "jido.agent.error",
          source: "/agent/#{data.agent.id}",
          data: %{
            agent_id: data.agent.id,
            turn_id: outcome.id,
            status: outcome.status,
            stage: outcome.stage,
            committed?: outcome.committed?,
            error: Error.to_map(outcome.error)
          }
        )

      {:continue, start_dispatch(signal, dispatch, data)}
    end
  end

  def decision(%Outcome{} = outcome, %State{error_policy: policy} = data)
      when is_function(policy, 2) do
    case policy.(outcome.error, outcome) do
      :continue -> {:continue, data}
      {:stop, stop_reason} -> {:stop, stop_reason, data}
      other -> {:stop, {:invalid_error_policy_result, other}, data}
    end
  rescue
    error -> {:stop, {:error_policy_failed, error}, data}
  catch
    kind, reason -> {:stop, {:error_policy_failed, {kind, reason}}, data}
  end

  @doc false
  def handle_result(%State{} = data, ref, result) do
    pending = Map.fetch!(data.error_policy_tasks, ref)
    release_task_result(pending)
    data = drop_task(data, ref)

    case result do
      :ok ->
        {:keep_state, data}

      {:error, reason} ->
        {:keep_state, record_dispatch_failure(data, reason)}

      other ->
        reason =
          Error.execution_error("Agent error Signal delivery returned an invalid result",
            details: %{result: other}
          )

        {:keep_state, record_dispatch_failure(data, reason)}
    end
  end

  @doc false
  def handle_down(%State{} = data, ref, reason) do
    pending = Map.fetch!(data.error_policy_tasks, ref)
    cancel_timer(pending.timer)
    data = drop_task(data, ref)

    error =
      Error.execution_error("Agent error Signal delivery task exited",
        details: %{reason: reason}
      )

    {:keep_state, record_dispatch_failure(data, error)}
  end

  @doc false
  def handle_timeout(%State{} = data, task_ref, timer) do
    pending = Map.fetch!(data.error_policy_tasks, task_ref)

    if pending.timer == timer do
      shutdown_task(pending.task)
      data = drop_task(data, task_ref)

      error =
        Error.timeout_error("Agent error Signal delivery timed out",
          timeout: dispatch_timeout(data)
        )

      {:keep_state, record_dispatch_failure(data, error)}
    else
      :keep_state_and_data
    end
  end

  @doc false
  def stop_all(%State{} = data) do
    Enum.each(data.error_policy_tasks, fn {_ref, pending} -> stop_task(pending) end)
    :ok
  end

  defp start_dispatch(signal, dispatch, %State{} = data) do
    if map_size(data.error_policy_tasks) >= @max_tasks do
      error =
        Error.execution_error("Agent error Signal delivery limit was reached",
          details: %{limit: @max_tasks}
        )

      record_dispatch_failure(data, error)
    else
      supervisor = Jido.task_supervisor_name(data.jido)
      jido = data.jido
      trace = TraceContext.capture()

      task =
        Task.Supervisor.async(supervisor, fn ->
          TraceContext.with_context(trace, fn ->
            DirectiveRuntime.dispatch_signal(signal, dispatch, jido)
          end)
        end)

      timeout = dispatch_timeout(data)
      timer = start_timer(timeout, task.ref)
      pending = %{task: task, timer: timer}
      %{data | error_policy_tasks: Map.put(data.error_policy_tasks, task.ref, pending)}
    end
  rescue
    error -> record_dispatch_failure(data, error)
  catch
    kind, reason -> record_dispatch_failure(data, {kind, reason})
  end

  defp dispatch_timeout(%State{directive_timeout: :infinity}),
    do: @dispatch_fallback_timeout

  defp dispatch_timeout(%State{directive_timeout: timeout}), do: timeout

  defp drop_task(%State{} = data, ref) do
    %{data | error_policy_tasks: Map.delete(data.error_policy_tasks, ref)}
  end

  defp record_dispatch_failure(%State{} = data, reason) do
    error = Debug.public_error(reason)

    Logger.error(
      "Agent error Signal delivery failed " <>
        "agent_id=#{data.agent.id} error_type=#{error.type} error_code=#{Error.code(reason)}"
    )

    Debug.record(data, :error_signal_delivery_failed, %{error: error})
  end

  defp start_timer(timeout, task_ref) do
    :erlang.start_timer(timeout, self(), {:error_policy_dispatch_timeout, task_ref})
  end

  defp release_task_result(%{task: %Task{ref: ref}, timer: timer}) do
    Process.demonitor(ref, [:flush])
    cancel_timer(timer)
  end

  defp stop_task(%{task: %Task{} = task, timer: timer}) do
    shutdown_task(task)
    cancel_timer(timer)
  end

  defp shutdown_task(%Task{} = task) do
    Task.shutdown(task, :brutal_kill)
  catch
    :exit, _reason -> :ok
  end

  defp cancel_timer(nil), do: :ok

  defp cancel_timer(timer) do
    _result = :erlang.cancel_timer(timer)
    :ok
  end
end
