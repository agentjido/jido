defmodule Jido.Test.Exec.RunnerHarness do
  @moduledoc false

  alias Jido.Exec.Runtime
  alias Jido.Instruction
  alias Runic.Runner
  alias Runic.Workflow

  def start(runner, id, target, params \\ %{}, context \\ %{}, opts \\ []) do
    with {:ok, instruction} <- Instruction.resolve(target, params, context),
         {:ok, instruction} <- Runtime.flow_instruction(instruction),
         :ok <- Runtime.portable(instruction),
         {:ok, workflow} <- Jido.Exec.compile(%{instruction | context: %{}}, []),
         :ok <- Jido.Exec.Node.Wait.validate_host(workflow),
         {:ok, policy, worker_opts} <- options(opts),
         {:ok, pid} <- Runner.start_workflow(runner, id, workflow, worker_opts) do
      case Runner.start_execution(
             runner,
             id,
             Jido.Exec.Fact.local_value(input(instruction)),
             execution_id: identity(id),
             run_context: %{
               _global:
                 instruction.context
                 |> Runtime.caller_context()
                 |> Map.put(:__jido_exec_max_concurrency__, worker_opts[:max_concurrency])
             },
             scheduler_policies: [{:default, policy}]
           ) do
        {:ok, _scope_id} ->
          {:ok, pid}

        {:error, reason} ->
          case Runner.cancel(runner, id) do
            :ok -> {:error, reason}
            {:error, _reason} = error -> error
          end
      end
    end
  end

  def resume(runner, id, context \\ %{}, opts \\ []) do
    with {:ok, context} <- context(context),
         :ok <- Runtime.validate_local(context, :context),
         {:ok, rehydration, fallback?, opts} <- rehydration(runner, opts),
         {:ok, policy, worker_opts} <- options(opts) do
      resume_opts =
        worker_opts ++
          [
            rehydration: rehydration,
            run_context: %{
              _global:
                context
                |> Runtime.caller_context()
                |> Map.put(:__jido_exec_max_concurrency__, worker_opts[:max_concurrency])
            },
            scheduler_policies: [{:default, policy}]
          ]

      case Runner.resume(runner, id, resume_opts) do
        {:error, {:unsupported_batch_rehydration, :hybrid}} when fallback? ->
          Runner.resume(runner, id, Keyword.put(resume_opts, :rehydration, :full))

        result ->
          result
      end
    end
  end

  def step(runner, id) do
    case Runner.step(runner, id) do
      :ok -> current_workflow(runner, id, :ok)
      {:error, :not_runnable} -> current_workflow(runner, id, :complete)
      {:error, :admission_stopped} -> stopped_workflow(runner, id)
      {:error, _reason} = error -> error
    end
  end

  def result(%Workflow{} = workflow), do: Jido.Exec.Result.project(workflow)

  def result(%Workflow{} = workflow, %Workflow.Execution{} = observation),
    do: Jido.Exec.result(workflow, observation)

  def result(runner, id) do
    case Runner.execution(runner, id, identity(id)) do
      {:ok, observation} ->
        with {:ok, workflow} <- Runner.get_workflow(runner, id) do
          Jido.Exec.result(workflow, observation)
        end

      {:error, :not_found} ->
        with {:ok, workflow} <- Runner.get_workflow(runner, id),
             {:ok, status} <- Runner.admission_status(runner, id) do
          if status.active_units > 0 or
               (status.status == :open and Workflow.is_runnable?(workflow)),
             do: {:error, incomplete(id, :execution_active)},
             else: Jido.Exec.Result.project(workflow)
        end
    end
  end

  defp input(%Instruction{kind: :flow, params: params}), do: params

  defp identity(id),
    do: Runic.Identity.digest(:execution, :erlang.term_to_binary(id, [:deterministic]))

  defp incomplete(id, reason) do
    Jido.Error.execution_error("Exec execution is not complete", %{
      execution_id: id,
      reason: reason,
      retry: false
    })
  end

  defp context(nil), do: {:ok, %{}}
  defp context(value) when is_map(value), do: {:ok, value}

  defp context(value) when is_list(value) do
    if Keyword.keyword?(value),
      do: {:ok, Map.new(value)},
      else: {:error, Jido.Error.validation_error("context must be a map or keyword list")}
  end

  defp context(_value),
    do: {:error, Jido.Error.validation_error("context must be a map or keyword list")}

  defp options(opts) when is_list(opts) do
    policy_keys = [:timeout, :max_attempts, :backoff, :base_delay_ms, :max_delay_ms]

    worker_keys = [
      :dispatch_mode,
      :max_concurrency,
      :on_complete,
      :checkpoint_strategy,
      :executor,
      :executor_opts,
      :scheduler,
      :scheduler_opts,
      :hooks,
      :promise_opts
    ]

    with true <- Keyword.keyword?(opts),
         [] <- Keyword.keys(opts) -- (policy_keys ++ worker_keys),
         {:ok, policy} <- policy(Keyword.take(opts, policy_keys)),
         worker_opts =
           opts
           |> Keyword.take(worker_keys)
           |> Keyword.put_new(:max_concurrency, default_max_concurrency())
           |> Keyword.put(:runnable_order, &observation_order/1),
         :ok <- validate_worker_options(worker_opts) do
      {:ok, policy, quiet_failure_log(worker_opts)}
    else
      false -> {:error, Jido.Error.config_error("execution options must be a keyword list")}
      [_ | _] = unknown -> {:error, Jido.Error.config_error("unknown managed execution options", %{options: unknown})}
      {:error, _reason} = error -> error
    end
  end

  defp options(_opts),
    do: {:error, Jido.Error.config_error("execution options must be a keyword list")}

  defp policy(opts) do
    timeout = Keyword.get(opts, :timeout, :infinity)
    max_attempts = Keyword.get(opts, :max_attempts, 1)
    backoff = Keyword.get(opts, :backoff, :none)
    base_delay_ms = Keyword.get(opts, :base_delay_ms, 0)
    max_delay_ms = Keyword.get(opts, :max_delay_ms, 0)

    cond do
      timeout != :infinity and not (is_integer(timeout) and timeout >= 0) ->
        {:error, Jido.Error.config_error("timeout must be non-negative or :infinity")}

      not (is_integer(max_attempts) and max_attempts >= 1) ->
        {:error, Jido.Error.config_error("max_attempts must be a positive integer")}

      backoff not in [:none, :linear, :exponential, :jitter] ->
        {:error, Jido.Error.config_error("invalid backoff policy")}

      not (is_integer(base_delay_ms) and base_delay_ms >= 0) ->
        {:error, Jido.Error.config_error("base_delay_ms must be non-negative")}

      not (is_integer(max_delay_ms) and max_delay_ms >= 0) ->
        {:error, Jido.Error.config_error("max_delay_ms must be non-negative")}

      true ->
        {:ok,
         %{
           timeout_ms: timeout,
           max_retries: max_attempts - 1,
           backoff: backoff,
           base_delay_ms: base_delay_ms,
           max_delay_ms: max_delay_ms,
           on_failure: :halt,
           retry_if: {Jido.Error, :retryable?, []},
           execution_mode: :durable
         }}
    end
  end

  defp rehydration(runner, opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      explicit? = Keyword.has_key?(opts, :rehydration)
      fact_store? = fact_store?(runner)
      default = if fact_store?, do: :hybrid, else: :full
      {mode, opts} = Keyword.pop(opts, :rehydration, default)

      cond do
        mode not in [:full, :hybrid, :lazy] ->
          {:error, Jido.Error.config_error("invalid managed execution option")}

        explicit? and mode in [:hybrid, :lazy] and not fact_store? ->
          {:error, Jido.Error.config_error("rehydration mode requires Runic fact storage")}

        true ->
          {:ok, mode, not explicit? and mode == :hybrid, opts}
      end
    else
      {:error, Jido.Error.config_error("execution options must be a keyword list")}
    end
  end

  defp rehydration(_runner, _opts),
    do: {:error, Jido.Error.config_error("execution options must be a keyword list")}

  defp fact_store?(runner) do
    {store, _state} = Runner.get_store(runner)
    function_exported?(store, :save_fact, 3) and function_exported?(store, :load_fact, 2)
  end

  defp validate_worker_options(opts) do
    Enum.reduce_while(opts, :ok, fn {key, value}, :ok ->
      if valid_worker_option?(key, value),
        do: {:cont, :ok},
        else: {:halt, {:error, Jido.Error.config_error("invalid managed execution option")}}
    end)
  end

  defp valid_worker_option?(:max_concurrency, value), do: is_integer(value) and value > 0
  defp valid_worker_option?(:dispatch_mode, value), do: value in [:automatic, :manual]
  defp valid_worker_option?(:checkpoint_strategy, {:every_n, n}), do: is_integer(n) and n > 0
  defp valid_worker_option?(:checkpoint_strategy, value), do: value in [:every_cycle, :on_complete, :manual]
  defp valid_worker_option?(key, value) when key in [:executor, :scheduler], do: is_atom(value)

  defp valid_worker_option?(key, value) when key in [:hooks, :executor_opts, :scheduler_opts, :promise_opts],
    do: Keyword.keyword?(value)

  defp valid_worker_option?(_key, _value), do: true

  defp default_max_concurrency do
    Application.get_env(:jido, :max_concurrency, min(System.schedulers_online(), 10))
  end

  defp observation_order(runnable) do
    {elem(Runic.Workflow.Runnable.order_key(runnable), 0), Map.get(runnable.node, :name),
     map_item_index(runnable.input_fact), Runic.Workflow.Runnable.activation_id(runnable)}
  end

  defp map_item_index(%Runic.Workflow.Fact{} = fact) do
    case Jido.Exec.Fact.value(fact) do
      {:jido_map_item, index, _id, _params} -> index
      _value -> 0
    end
  end

  defp map_item_index(_fact), do: 0

  defp quiet_failure_log(worker_opts) do
    hooks = Keyword.get(worker_opts, :hooks, [])
    failed = hooks[:on_failed]

    on_failed = fn runnable, error, state ->
      if failed, do: failed.(runnable, error, state)
      Runtime.quiet_failure_log()
    end

    Keyword.put(worker_opts, :hooks, Keyword.put(hooks, :on_failed, on_failed))
  end

  defp current_workflow(runner, id, status) do
    case Runner.get_workflow(runner, id) do
      {:ok, %Workflow{} = workflow} -> {status, workflow}
      {:error, _reason} = error -> error
    end
  end

  defp stopped_workflow(runner, id) do
    case Runner.admission_status(runner, id) do
      {:ok, %{active_units: 0}} -> current_workflow(runner, id, :complete)
      {:ok, _status} -> {:error, :busy}
      {:error, _reason} = error -> error
    end
  end
end
