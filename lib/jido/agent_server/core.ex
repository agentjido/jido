defmodule Jido.AgentServer.Core do
  @moduledoc false

  @max_timeout 4_294_967_295
  @runtime_defaults [
    turn_timeout: 60_000,
    exec_opts: [],
    error_policy: :log_only,
    error_policy_timeout: 5_000,
    debug: false,
    debug_max_events: 100,
    max_postponed_signals: 1_000,
    max_directives_per_turn: 1_000,
    directive_timeout: 5_000,
    directive_handler: nil,
    default_dispatch: nil,
    readiness_timeout: 5_000,
    commit_timeout: 5_000,
    persistence: false,
    persistence_mode: :create,
    persistence_timeout: 5_000,
    idle_timeout: :infinity,
    idle_policy: :stop
  ]
  @runtime_keys Keyword.keys(@runtime_defaults)
  @startup_keys @runtime_keys ++ [:agent, :name, :runner, :jido, :partition]
  @exec_keys [
    :timeout,
    :max_attempts,
    :backoff,
    :base_delay_ms,
    :max_delay_ms,
    :max_concurrency,
    :hooks
  ]
  @hook_arities [
    on_dispatch: 2,
    on_complete: 3,
    on_failed: 3,
    on_idle: 1,
    on_persistence_error: 3,
    transform_runnables: 2
  ]
  @error_signal "jido.agent_server.error"

  require Logger

  alias Jido.Agent.Command
  alias Jido.Tracing.Context, as: TraceContext

  def max_timeout, do: @max_timeout
  def runtime_defaults, do: @runtime_defaults
  def runtime_keys, do: @runtime_keys
  def startup_keys, do: @startup_keys

  def with_turn_timeout(opts) do
    if Keyword.has_key?(opts, :turn_timeout) do
      {:ok, opts}
    else
      config = Application.get_env(:jido, Jido.AgentServer, [])

      cond do
        not is_list(config) or not Keyword.keyword?(config) ->
          invalid_options("AgentServer application configuration must be a keyword list")

        Keyword.keys(config) -- [:turn_timeout] != [] ->
          invalid_options("unknown AgentServer application configuration options")

        true ->
          {:ok,
           Keyword.put(
             opts,
             :turn_timeout,
             Keyword.get(config, :turn_timeout, @runtime_defaults[:turn_timeout])
           )}
      end
    end
  end

  def validate_runtime(opts) do
    with :ok <-
           validate_setting(
             opts[:turn_timeout] == :infinity or
               (is_integer(opts[:turn_timeout]) and opts[:turn_timeout] >= 0),
             :turn_timeout
           ),
         :ok <- validate_exec(opts[:exec_opts]),
         :ok <- validate_error_policy(opts[:error_policy]),
         :ok <- validate_timeout(opts, :error_policy_timeout),
         :ok <- validate_limit(opts, :max_postponed_signals),
         :ok <- validate_setting(is_boolean(opts[:debug]), :debug),
         do:
           validate_setting(
             is_integer(opts[:debug_max_events]) and opts[:debug_max_events] in 1..10_000,
             :debug_max_events
           )
  end

  def validate_timeout(opts, key, finite? \\ true) do
    value = Keyword.fetch!(opts, key)
    validate_setting((not finite? or value != :infinity) and validate_wait(value) == :ok, key)
  end

  def validate_limit(opts, key) do
    value = Keyword.fetch!(opts, key)
    validate_setting(value == :infinity or (is_integer(value) and value >= 0), key)
  end

  def validate_setting(true, _key), do: :ok
  def validate_setting(false, key), do: invalid_options("invalid #{key}")

  def validate_wait(:infinity), do: :ok
  def validate_wait(timeout) when is_integer(timeout) and timeout in 0..@max_timeout, do: :ok

  def validate_wait(_timeout),
    do: invalid_options("timeout must be in 0..#{@max_timeout} milliseconds or :infinity")

  def control_options(opts) do
    if is_list(opts) and Keyword.keyword?(opts) and
         Keyword.keys(opts) -- [:active, :timeout] == [] do
      active = Keyword.get(opts, :active, :finish)
      timeout = Keyword.get(opts, :timeout, 5_000)

      with :ok <- validate_setting(active in [:finish, :cancel], :active),
           :ok <- validate_timeout([timeout: timeout], :timeout),
           do: {:ok, active, timeout}
    else
      invalid_options("invalid control options")
    end
  end

  def control_wait(timeout), do: min(@max_timeout, timeout + 1_000)

  def turn_context(opts, allowed) do
    if is_list(opts) and Keyword.keyword?(opts) and Keyword.keys(opts) -- allowed == [] do
      with {:ok, context} <- Command.normalize_context(Keyword.get(opts, :context)),
           :ok <- Command.validate_caller_context(context) do
        if Enum.any?([:turn_id, :trace_context], &Map.has_key?(context, &1)),
          do: invalid_options(":turn_id and :trace_context are reserved"),
          else: {:ok, context}
      end
    else
      invalid_options("invalid turn options")
    end
  end

  def admission_deadline(opts) do
    with {:ok, timeout} <- admission_timeout(opts) do
      deadline =
        if timeout == :infinity,
          do: :infinity,
          else: {node(), System.monotonic_time(:millisecond) + timeout}

      {:ok, deadline}
    end
  end

  def admission_timeout(opts) do
    timeout = Keyword.get(opts, :admission_timeout, 5_000)
    with :ok <- validate_wait(timeout), do: {:ok, timeout}
  end

  def admission_status(:infinity), do: :ok

  def admission_status({origin, _deadline}) when origin != node(),
    do: {:error, :admission_clock_unavailable}

  def admission_status({_origin, deadline}) do
    if System.monotonic_time(:millisecond) >= deadline,
      do: {:error, :admission_timeout},
      else: :ok
  end

  def queue_decision(postponed, token, limit) do
    count = MapSet.size(postponed)

    cond do
      MapSet.member?(postponed, token) -> :duplicate
      limit != :infinity and count >= limit -> {:overloaded, count}
      true -> :accept
    end
  end

  def execution_policy(opts) do
    %{
      timeout_ms: Keyword.get(opts, :timeout, :infinity),
      max_retries: Keyword.get(opts, :max_attempts, 1) - 1,
      backoff: Keyword.get(opts, :backoff, :none),
      base_delay_ms: Keyword.get(opts, :base_delay_ms, 500),
      max_delay_ms: Keyword.get(opts, :max_delay_ms, 30_000),
      on_failure: :halt,
      retry_if: {Jido.Action.Error, :retryable?, []}
    }
  end

  def execution_hooks(hooks, trace) do
    hooks = Enum.map(hooks, fn {name, fun} -> {name, safe_hook(name, fun)} end)
    dispatch = Keyword.get(hooks, :on_dispatch)
    failed = Keyword.get(hooks, :on_failed)

    hooks
    |> Keyword.put(:on_dispatch, fn runnable, state ->
      Logger.metadata(Map.to_list(trace || %{}))
      TraceContext.put(trace)
      if dispatch, do: dispatch.(runnable, state)
    end)
    |> Keyword.put(:on_failed, fn runnable, error, state ->
      try do
        if failed, do: failed.(runnable, error, state)
      after
        Logger.put_process_level(self(), :error)
      end
    end)
  end

  def reentrant?(:cast, _data), do: false
  def reentrant?(_type, %{active: nil}), do: false

  def reentrant?({:call, {caller, _tag}}, data) do
    Enum.any?(
      [data.active.worker, operation_pid(data.active.operation)],
      fn root -> is_pid(root) and owned_process?(caller, root, [], 0) end
    )
  end

  def bootstrap_caller?(_from, %{bootstrap: nil}), do: false

  def bootstrap_caller?({caller, _}, data),
    do: owned_process?(caller, data.bootstrap.task.pid, [], 0)

  def owned_process?(pid, root, _visited, _depth) when pid == root, do: true
  def owned_process?(pid, _root, _visited, _depth) when pid == self(), do: false

  def owned_process?(pid, _root, _visited, depth) when node(pid) != node() or depth >= 8,
    do: false

  def owned_process?(pid, root, visited, depth) do
    if pid in visited do
      false
    else
      callers =
        case Process.info(pid, :dictionary) do
          {:dictionary, dictionary} -> Keyword.get(dictionary, :"$callers", [])
          nil -> []
        end

      Enum.any?(
        Enum.filter(List.wrap(callers), &is_pid/1),
        &owned_process?(&1, root, [pid | visited], depth + 1)
      )
    end
  end

  def outcome_status(:cancelled), do: :cancelled
  def outcome_status(:turn_timeout), do: :timed_out
  def outcome_status(_reason), do: :failed

  def next_error_count(:failed, count), do: count + 1
  def next_error_count(_status, count), do: count

  def outcome(active, state_version, status, stage, committed, count) do
    %{
      turn_id: active.turn_id,
      signal_id: active.signal_id,
      status: status,
      stage: stage,
      committed?: committed,
      state_version_before: active.start_version,
      state_version_after: state_version,
      directive_count: count,
      duration_ms:
        max(
          System.convert_time_unit(
            System.monotonic_time() - active.span.at,
            :native,
            :millisecond
          ),
          0
        )
    }
  end

  def retain_history(history, _outcome, false, _limit), do: history

  def retain_history(history, outcome, true, limit) do
    queue = :queue.in(outcome, history)
    if :queue.len(queue) > limit, do: elem(:queue.out(queue), 1), else: queue
  end

  def failure_decision(:log_only, _count, _signal_type), do: {:complete, :continue}

  def failure_decision(:stop_on_error, _count, _signal_type),
    do: {:complete, {:stop, :agent_error}}

  def failure_decision({:max_errors, max}, count, _signal_type) do
    decision = if count >= max, do: {:stop, :max_agent_errors}, else: :continue
    {:complete, decision}
  end

  def failure_decision({:emit_signal, _target}, _count, @error_signal),
    do: {:complete, :continue}

  def failure_decision(_policy, _count, _signal_type), do: :run

  def active_status(nil, _phase), do: nil

  def active_status(active, phase) do
    active
    |> Map.take([:turn_id, :signal_id, :start_version])
    |> Map.put(
      :committed_version,
      if(active.outcome && active.outcome.committed?,
        do: active.outcome.state_version_after,
        else: nil
      )
    )
    |> Map.put(:stage, phase)
    |> Map.put(:worker_pid, active.worker)
  end

  def invalid_options(message),
    do: {:error, Jido.Error.validation_error(message, kind: :config)}

  defp validate_exec(opts) do
    if is_list(opts) and Keyword.keyword?(opts) and Keyword.keys(opts) -- @exec_keys == [] and
         Enum.all?(opts, fn {key, value} -> valid_exec?(key, value) end),
       do: :ok,
       else: invalid_options("invalid exec_opts")
  end

  defp valid_exec?(:timeout, value), do: validate_wait(value) == :ok

  defp valid_exec?(key, value) when key in [:base_delay_ms, :max_delay_ms],
    do: value != :infinity and validate_wait(value) == :ok

  defp valid_exec?(key, value) when key in [:max_attempts, :max_concurrency],
    do: is_integer(value) and value > 0

  defp valid_exec?(:backoff, value), do: value in [:none, :linear, :exponential, :jitter]

  defp valid_exec?(:hooks, hooks) do
    is_list(hooks) and Keyword.keyword?(hooks) and
      Enum.all?(hooks, fn {key, fun} ->
        case Keyword.fetch(@hook_arities, key) do
          {:ok, arity} -> is_function(fun, arity)
          :error -> false
        end
      end)
  end

  defp validate_error_policy(policy) when policy in [:log_only, :stop_on_error], do: :ok
  defp validate_error_policy({:max_errors, count}) when is_integer(count) and count > 0, do: :ok
  defp validate_error_policy(fun) when is_function(fun, 2), do: :ok

  defp validate_error_policy({:emit_signal, target}) do
    case Jido.Signal.Dispatch.validate_opts(target) do
      {:ok, _} -> :ok
      {:error, _} -> invalid_options("invalid error_policy Signal destination")
    end
  end

  defp validate_error_policy(_), do: invalid_options("invalid error_policy")

  defp safe_hook(:transform_runnables, fun),
    do: fn runnables, state -> invoke_hook(fun, [runnables, state], runnables) end

  defp safe_hook(:on_dispatch, fun),
    do: fn runnable, state -> invoke_hook(fun, [runnable, state], :ok) end

  defp safe_hook(:on_idle, fun), do: fn state -> invoke_hook(fun, [state], :ok) end

  defp safe_hook(_name, fun),
    do: fn first, second, state -> invoke_hook(fun, [first, second, state], :ok) end

  defp invoke_hook(fun, args, fallback) do
    apply(fun, args)
  catch
    _, _ ->
      Logger.warning("AgentServer execution hook failed")
      fallback
  end

  defp operation_pid(nil), do: nil
  defp operation_pid(operation), do: operation.task.pid
end
