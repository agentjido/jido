defmodule Jido.AgentServer.FailurePolicy do
  @moduledoc false

  alias Jido.AgentServer.TaskSupport

  require Logger

  alias Jido.Agent.Turn.Outcome
  alias Jido.AgentServer.{DirectiveRuntime, Inspection, Shutdown, State}
  alias Jido.AgentServer.Signal.Error, as: ErrorSignal
  alias Jido.Error
  alias Jido.Signal

  @max_error_policy_tasks 32

  def decide(%Outcome{}, %State{error_policy: :log_only} = data),
    do: {:continue, data}

  def decide(%Outcome{} = outcome, %State{error_policy: :stop_on_error} = data),
    do: {:stop, {:agent_error, outcome.error}, data}

  def decide(
        %Outcome{} = outcome,
        %State{error_policy: {:max_errors, max}} = data
      ) do
    if data.error_count >= max,
      do: {:stop, {:max_agent_errors, outcome.error}, data},
      else: {:continue, data}
  end

  def decide(
        %Outcome{} = outcome,
        %State{error_policy: {:emit_signal, dispatch}} = data
      ) do
    source_signal = outcome.effective_signal || outcome.source_signal

    if source_signal.type != ErrorSignal.type() do
      signal =
        ErrorSignal.new!(
          %{
            agent_id: data.agent.id,
            turn_id: outcome.id,
            status: outcome.status,
            stage: outcome.stage,
            committed?: outcome.committed?,
            error: Error.to_map(outcome.error)
          },
          source: "/agent/#{data.agent.id}"
        )

      signal =
        with id when is_binary(id) and byte_size(id) > 0 <- source_signal.id,
             :ok <- Signal.validate_utf8_string(id, []),
             {:ok, causal} <- Signal.put_context(signal, "jidocausationid", id) do
          causal
        else
          _invalid -> signal
        end

      signal =
        with %Jido.Signal.Trace{} = trace <- Jido.Signal.Trace.get(source_signal),
             {:ok, traced} <- Jido.Signal.Trace.put(signal, trace) do
          traced
        else
          _unavailable -> signal
        end

      data = start_error_policy_dispatch(signal, dispatch, data)

      {:continue, data}
    else
      {:continue, data}
    end
  end

  def decide(%Outcome{} = outcome, %State{error_policy: policy} = data)
      when is_function(policy, 2) do
    start_custom_error_policy(policy, outcome, data)
  end

  defp start_custom_error_policy(policy, outcome, %State{} = data) do
    if map_size(data.error_policy_tasks) >= @max_error_policy_tasks do
      {:stop, :error_policy_task_limit, data}
    else
      next_data =
        start_policy_task(data, :custom, fn ->
          try do
            policy.(outcome.error, outcome)
          rescue
            error -> {:stop, {:error_policy_failed, error}}
          catch
            kind, reason -> {:stop, {:error_policy_failed, {kind, reason}}}
          end
        end)

      {:continue, next_data}
    end
  rescue
    error -> {:stop, {:error_policy_start_failed, error}, data}
  catch
    kind, reason -> {:stop, {:error_policy_start_failed, {kind, reason}}, data}
  end

  def settle_custom(:continue, data), do: {:keep_state, data}

  def settle_custom({:stop, reason}, data),
    do: {:stop, Shutdown.normalize_reason(reason), data}

  def settle_custom(other, data),
    do: {:stop, Shutdown.normalize_reason({:invalid_error_policy_result, other}), data}

  defp start_error_policy_dispatch(signal, dispatch, %State{} = data) do
    if map_size(data.error_policy_tasks) >= @max_error_policy_tasks do
      error =
        Error.execution_error("Agent error Signal delivery limit was reached",
          details: %{limit: @max_error_policy_tasks}
        )

      record_dispatch_failure(data, error)
    else
      jido = data.jido

      start_policy_task(data, :dispatch, fn ->
        DirectiveRuntime.dispatch_signal(signal, dispatch, jido)
      end)
    end
  rescue
    error -> record_dispatch_failure(data, error)
  catch
    kind, reason -> record_dispatch_failure(data, {kind, reason})
  end

  def dispatch_timeout(%State{directive_timeout: timeout}),
    do: TaskSupport.finite_timeout(timeout)

  defp start_policy_task(data, kind, fun) do
    pending =
      TaskSupport.start_traced(
        data.jido,
        fun,
        dispatch_timeout(data),
        :error_policy_dispatch_timeout
      )
      |> Map.put(:kind, kind)

    task = pending.task
    %{data | error_policy_tasks: Map.put(data.error_policy_tasks, task.ref, pending)}
  end

  def drop_task(%State{} = data, ref) do
    %{data | error_policy_tasks: Map.delete(data.error_policy_tasks, ref)}
  end

  def record_dispatch_failure(%State{} = data, reason) do
    error = Inspection.public_error(reason)

    Logger.error(
      "Agent error Signal delivery failed " <>
        "agent_id=#{data.agent.id} error_type=#{error.type} error_code=#{Error.code(reason)}"
    )

    Inspection.record_event(data, :error_signal_delivery_failed, %{error: error})
  end

  def task_result(ref, result, %State{} = data) do
    pending = Map.fetch!(data.error_policy_tasks, ref)
    TaskSupport.release_task_result(pending)
    data = drop_task(data, ref)

    case Map.get(pending, :kind, :dispatch) do
      :custom ->
        settle_custom(result, data)

      :dispatch ->
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
  end

  def task_down(ref, reason, %State{} = data) do
    pending = Map.fetch!(data.error_policy_tasks, ref)
    TaskSupport.cancel_task_timer(pending.timer)
    data = drop_task(data, ref)

    case Map.get(pending, :kind, :dispatch) do
      :custom ->
        {:stop, Shutdown.normalize_reason({:error_policy_task_failed, reason}), data}

      :dispatch ->
        error =
          Error.execution_error("Agent error Signal delivery task exited",
            details: %{reason: reason}
          )

        {:keep_state, record_dispatch_failure(data, error)}
    end
  end

  def task_timeout(task_ref, %State{} = data) do
    pending = Map.fetch!(data.error_policy_tasks, task_ref)
    TaskSupport.shutdown_task(pending.task)
    data = drop_task(data, task_ref)

    case Map.get(pending, :kind, :dispatch) do
      :custom ->
        {:stop, Shutdown.normalize_reason({:error_policy_timeout, dispatch_timeout(data)}), data}

      :dispatch ->
        error =
          Error.timeout_error("Agent error Signal delivery timed out",
            timeout: dispatch_timeout(data)
          )

        {:keep_state, record_dispatch_failure(data, error)}
    end
  end
end
