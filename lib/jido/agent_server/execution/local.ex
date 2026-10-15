defmodule Jido.AgentServer.Execution.Local do
  @moduledoc false

  alias Jido.Action.Error
  alias Jido.Exec.{Fact, Frame, Validation}
  alias Jido.Instruction
  alias Runic.Workflow.{Runnable, SchedulerPolicy}

  @policy_keys [:timeout, :max_attempts, :backoff, :base_delay_ms, :max_delay_ms]
  @worker_keys [
    :owner,
    :max_concurrency,
    :on_complete,
    :executor,
    :executor_opts,
    :scheduler,
    :scheduler_opts,
    :hooks,
    :promise_opts
  ]

  def start(runner, id, target, params, context, opts) do
    with {:ok, policy, worker_opts} <- options(opts),
         {:ok, instruction} <- Instruction.resolve(target, params, context),
         {:ok, input} <- input(instruction),
         {:ok, workflow} <- Jido.Exec.compile(%{instruction | context: %{}}),
         {:ok, pid} <- Runic.Runner.start_workflow(runner, id, workflow, worker_opts) do
      case Runic.Runner.start_execution(runner, id, Fact.local_value(input),
             run_context: %{_global: instruction.context},
             scheduler_policies: [{:default, Map.from_struct(policy)}]
           ) do
        {:ok, execution_id} ->
          {:ok, pid, execution_id}

        {:error, error} ->
          case Runic.Runner.cancel(runner, id) do
            :ok -> {:error, normalize_error(error)}
            {:error, reason} -> {:error, normalize_error(reason)}
          end
      end
    else
      {:error, error} -> {:error, normalize_error(error)}
    end
  end

  def result(runner, id, execution_id) do
    with {:ok, observation} <- Runic.Runner.execution(runner, id, execution_id),
         {:ok, workflow} <- Runic.Runner.get_workflow(runner, id) do
      Jido.Exec.result(workflow, observation)
    else
      {:error, error} -> {:error, normalize_error(error)}
    end
  end

  defp input(%Instruction{kind: :action}), do: {:ok, %{}}

  defp input(%Instruction{kind: :flow} = instruction) do
    with {:ok, params} <-
           Validation.input(instruction.target, instruction.params, %{phase: :flow_input}) do
      {:ok, Frame.new(params)}
    end
  end

  defp options(opts) do
    case Keyword.keys(opts) -- (@policy_keys ++ @worker_keys) do
      [] ->
        with :ok <- validate_options(opts) do
          policy = %SchedulerPolicy{
            timeout_ms: Keyword.get(opts, :timeout, :infinity),
            max_retries: Keyword.get(opts, :max_attempts, 1) - 1,
            backoff: Keyword.get(opts, :backoff, :none),
            base_delay_ms: Keyword.get(opts, :base_delay_ms, 0),
            max_delay_ms: Keyword.get(opts, :max_delay_ms, 0),
            retry_if: {Jido.Action.Error, :retryable?, []}
          }

          worker_opts =
            opts
            |> Keyword.take(@worker_keys)
            |> Keyword.put(:checkpoint_strategy, :manual)
            |> Keyword.put(:runnable_order, &runnable_order/1)
            |> Keyword.put(:hooks, failure_hooks(Keyword.get(opts, :hooks, [])))

          {:ok, policy, worker_opts}
        end

      unknown ->
        {:error, Error.config_error("unknown local execution options", %{options: unknown})}
    end
  end

  defp validate_options(opts) do
    Enum.reduce_while(opts, :ok, fn {key, value}, :ok ->
      if valid_option?(key, value),
        do: {:cont, :ok},
        else:
          {:halt,
           {:error,
            Error.config_error("invalid local execution option", %{option: key, value: value})}}
    end)
  end

  defp valid_option?(:timeout, :infinity), do: true

  defp valid_option?(key, value) when key in [:timeout, :base_delay_ms, :max_delay_ms],
    do: is_integer(value) and value >= 0

  defp valid_option?(key, value) when key in [:max_attempts, :max_concurrency],
    do: is_integer(value) and value > 0

  defp valid_option?(:backoff, value), do: value in [:none, :linear, :exponential, :jitter]

  defp valid_option?(key, value) when key in [:executor, :scheduler],
    do: is_atom(value) and match?({:module, _}, Code.ensure_loaded(value))

  defp valid_option?(key, value)
       when key in [:executor_opts, :scheduler_opts, :hooks, :promise_opts],
       do: is_list(value) and Keyword.keyword?(value)

  defp valid_option?(_key, _value), do: true

  defp failure_hooks(hooks) do
    callback = Keyword.get(hooks, :on_failed)

    Keyword.put(hooks, :on_failed, fn runnable, error, state ->
      try do
        if is_function(callback, 3), do: callback.(runnable, error, state)
      after
        # Runic logs raw failed values after this hook. This Worker runs one Turn
        # and stops on failure. Core reports its error through the redaction boundary.
        Logger.put_process_level(self(), :error)
      end
    end)
  end

  # Keep the Action/Flow causal order when more than one node is ready.
  defp runnable_order(runnable) do
    index =
      case Fact.value(runnable.input_fact) do
        {:jido_map_item, index, _id, _params} -> index
        _value -> 0
      end

    {elem(Runnable.order_key(runnable), 0), Map.get(runnable.node, :name), index,
     Runnable.activation_id(runnable)}
  end

  defp normalize_error(error) when is_exception(error), do: error

  defp normalize_error(reason),
    do: Error.execution_error("Local execution failed", %{reason: reason})
end
