defmodule Jido.Durable do
  @moduledoc """
  Runs persisted Flows with `Jido.Signal` input.

  Durable execution is independent of Agents and AgentServer. It uses the
  Runner and persistence adapter of a running named Jido instance. Durable
  operations always use the persistence adapter configured on that instance.
  The execution reference is portable and contains no process identity.

  `start/4` and `resume/3` run until the Flow completes, fails, becomes
  uncertain, or opens a wait. Each authored Flow component boundary is
  checkpointed before the next component starts. Work inside an unfinished
  composite component can repeat after recovery.

  `signal/5` saves one Signal as input to an open wait, then continues the Flow
  until its next durable stop. Equal retries are inert because the Signal ID
  identifies the input receipt.

  Timed waits expose `Jido.Durable.Status.next_wake_at`. A host can call
  `resume/3` at or after that UTC Unix time. A cron host calculates an
  occurrence and delivers it as a Signal; Durable does not own a scheduler.
  """

  alias Jido.Durable.{Execution, Ref, Runtime, Status}
  alias Jido.Exec.Runtime, as: ExecRuntime
  alias Jido.Persistence.ContinuationStore
  alias Jido.Signal

  @metadata_fact {:jido_durable, 1, :execution}
  @start_option_keys [:id, :context, :exec_opts, :operation_timeout, :now]
  @resume_option_keys [:operation_timeout, :now]
  @signal_option_keys [:operation_timeout, :now]

  @typedoc "One durable operation result."
  @type operation_result :: {:ok, Status.t()} | {:error, term()}

  @doc "Builds a portable reference without starting work."
  @spec ref(atom(), String.t()) :: {:ok, Ref.t()} | {:error, term()}
  def ref(jido, id), do: Ref.new(jido, id)

  @doc "Starts or idempotently resumes one durable Flow for the initial Signal."
  @spec start(atom(), term(), Signal.t(), keyword()) :: operation_result()
  def start(jido, target, signal, opts \\ [])

  def start(jido, target, %Signal{} = signal, opts) do
    with :ok <- validate_options(opts, @start_option_keys),
         {:ok, config} <- persistence(jido),
         {:ok, ref} <- Ref.new(jido, Keyword.get(opts, :id, signal.id)),
         {:ok, params} <- signal_params(signal),
         {:ok, context} <- durable_context(signal, Keyword.get(opts, :context, %{})),
         {:ok, exec_opts} <- exec_options(Keyword.get(opts, :exec_opts, [])),
         {:ok, instruction} <- durable_instruction(target, params, context),
         {:ok, execution} <- Execution.new(ref, instruction, signal, context, exec_opts),
         :ok <- Runtime.register(jido, Ref.execution_id(ref), config),
         :ok <- save_execution(jido, execution),
         do: run(jido, execution, config, opts)
  end

  def start(_jido, _target, _signal, _opts),
    do: {:error, Jido.Error.validation_error("durable input must be a Jido.Signal")}

  @doc "Resumes a stored execution and runs until its next durable stop."
  @spec resume(atom(), Ref.t(), keyword()) :: operation_result()
  def resume(jido, ref, opts \\ [])

  def resume(jido, %Ref{} = ref, opts) do
    with :ok <- validate_options(opts, @resume_option_keys),
         :ok <- validate_ref_instance(jido, ref),
         {:ok, config} <- persistence(jido),
         {:ok, execution} <- load_execution(jido, ref, config),
         do: run(jido, execution, config, opts)
  end

  def resume(_jido, _ref, _opts), do: invalid_ref()

  @doc "Saves one Signal for an addressed wait and continues the durable Flow."
  @spec signal(atom(), Ref.t(), Jido.Exec.Wait.id(), Signal.t(), keyword()) ::
          operation_result()
  def signal(jido, ref, wait_id, signal, opts \\ [])

  def signal(jido, %Ref{} = ref, wait_id, %Signal{} = signal, opts) do
    with :ok <- validate_options(opts, @signal_option_keys),
         :ok <- validate_ref_instance(jido, ref),
         {:ok, config} <- persistence(jido),
         {:ok, execution} <- load_execution(jido, ref, config),
         {:ok, input} <- Jido.Exec.Wait.input(wait_id, signal) do
      case Runtime.accept_input(
             jido,
             Ref.execution_id(ref),
             config,
             input,
             now_option(opts)
           ) do
        :ok -> run(jido, execution, config, opts)
        {:rejected, reason} -> {:error, reason}
        result -> result
      end
    end
  end

  def signal(_jido, _ref, _wait_id, _signal, _opts),
    do: {:error, Jido.Error.validation_error("durable wait input must be a Jido.Signal")}

  @doc "Reads the last committed durable execution status."
  @spec status(atom(), Ref.t()) :: operation_result()
  def status(jido, %Ref{} = ref) do
    with :ok <- validate_ref_instance(jido, ref),
         {:ok, config} <- persistence(jido),
         {:ok, _execution} <- load_execution(jido, ref, config),
         {:ok, workflow} <- Runtime.workflow(jido, Ref.execution_id(ref), config),
         true <- not is_nil(workflow) do
      {:ok, Status.new(ref, workflow, active?(jido, ref))}
    else
      false -> {:error, :not_found}
      error -> error
    end
  end

  def status(_jido, _ref), do: invalid_ref()

  @doc "Reads the normal `Jido.Exec` result from the last committed state."
  @spec result(atom(), Ref.t()) :: Jido.Exec.exec_result()
  def result(jido, %Ref{} = ref) do
    with :ok <- validate_ref_instance(jido, ref),
         {:ok, config} <- persistence(jido),
         {:ok, _execution} <- load_execution(jido, ref, config),
         {:ok, workflow} when not is_nil(workflow) <-
           Runtime.workflow(jido, Ref.execution_id(ref), config) do
      Jido.Exec.Result.project(workflow)
    else
      {:ok, nil} -> {:error, :not_found}
      error -> error
    end
  end

  def result(_jido, _ref), do: invalid_ref()

  defp run(jido, %Execution{} = execution, config, opts) do
    runner = Jido.Instance.Names.exec_runner(jido)
    id = Ref.execution_id(execution.ref)
    now = Keyword.get(opts, :now, System.system_time(:millisecond))
    timeout = Keyword.get(opts, :operation_timeout, :infinity)
    max_concurrency = Keyword.get(execution.exec_opts, :max_concurrency, 1)

    open_opts = [
      instance: jido,
      persistence: config,
      owner: self(),
      hooks: [],
      policy: Runtime.execution_policy(execution.exec_opts),
      max_concurrency: max_concurrency,
      now: now
    ]

    case Runtime.open(runner, id, execution.instruction, execution.context, open_opts) do
      {:ok, _worker, ^id} -> advance_until_stop(jido, execution.ref, config, runner, timeout)
      {:waiting, _waits, _next_wake_at} -> committed_status(jido, execution.ref, config, runner)
      {:error, _reason} = error -> error
    end
  end

  defp advance_until_stop(jido, ref, config, runner, timeout) do
    id = Ref.execution_id(ref)

    case Runtime.advance(runner, id) do
      :running ->
        receive do
          {:jido_durable_advance, ^id} ->
            advance_until_stop(jido, ref, config, runner, timeout)
        after
          timeout_value(timeout) ->
            {:error,
             Jido.Error.execution_error("durable execution did not reach a stop before timeout", %{
               execution_id: id,
               reason: :timeout,
               retry: true
             })}
        end

      :complete ->
        committed_status(jido, ref, config, runner)

      {:waiting, _waits, _next_wake_at} ->
        committed_status(jido, ref, config, runner)

      {:error, _reason} = error ->
        _ = Runtime.suspend(runner, id)
        error
    end
  end

  defp committed_status(jido, ref, config, runner) do
    id = Ref.execution_id(ref)

    with :ok <- Runtime.suspend(runner, id),
         {:ok, workflow} when not is_nil(workflow) <- Runtime.workflow(jido, id, config) do
      {:ok, Status.new(ref, workflow)}
    else
      {:ok, nil} -> {:error, :not_found}
      error -> error
    end
  end

  defp save_execution(jido, %Execution{ref: ref} = execution),
    do: save_execution(jido, Ref.execution_id(ref), execution, 1)

  defp save_execution(jido, id, execution, retries) do
    case ContinuationStore.load_fact(id, @metadata_fact, jido) do
      {:ok, %Execution{} = stored} ->
        compare_execution(stored, execution)

      {:error, :not_found} ->
        case ContinuationStore.save_fact(id, @metadata_fact, execution, jido) do
          {:error, :fact_value_conflict} when retries > 0 ->
            save_execution(jido, id, execution, retries - 1)

          result ->
            result
        end

      {:ok, _other} ->
        {:error, :invalid_execution_checkpoint}

      error ->
        error
    end
  end

  defp compare_execution(execution, execution), do: :ok

  defp compare_execution(%Execution{fingerprint: stored}, %Execution{fingerprint: requested})
       when stored != requested,
       do: {:error, :execution_definition_changed}

  defp compare_execution(_stored, _requested), do: {:error, :execution_input_changed}

  defp load_execution(jido, %Ref{} = ref, config) do
    id = Ref.execution_id(ref)

    with :ok <- Runtime.register(jido, id, config),
         {:ok, %Execution{} = execution} <-
           ContinuationStore.load_fact(id, @metadata_fact, jido),
         true <- execution.ref == ref,
         :ok <- Execution.validate(execution) do
      {:ok, execution}
    else
      false -> {:error, :invalid_execution_checkpoint}
      {:ok, _other} -> {:error, :invalid_execution_checkpoint}
      error -> error
    end
  end

  defp durable_instruction(target, params, context) do
    with {:ok, instruction} <- Jido.Instruction.resolve(target, params, context),
         {:ok, instruction} <- ExecRuntime.flow_instruction(instruction),
         :ok <- ExecRuntime.portable(instruction) do
      {:ok, instruction}
    end
  end

  defp signal_params(%Signal{data: nil}), do: {:ok, %{}}
  defp signal_params(%Signal{data: data}) when is_map(data) and not is_struct(data), do: {:ok, data}

  defp signal_params(%Signal{data: data}) when is_list(data) do
    if Keyword.keyword?(data),
      do: {:ok, Map.new(data)},
      else: invalid("durable Signal data must be a map, keyword list, or nil", %{data: data})
  end

  defp signal_params(%Signal{data: data}),
    do: invalid("durable Signal data must be a map, keyword list, or nil", %{data: data})

  defp durable_context(signal, context) when is_map(context) and not is_struct(context) do
    context = context |> ExecRuntime.caller_context() |> Map.put(:signal, signal)

    with :ok <- ExecRuntime.validate_local(context, :context), do: {:ok, context}
  end

  defp durable_context(_signal, context),
    do: invalid("durable context must be a plain map", %{context: context})

  defp exec_options(opts) do
    with :ok <- Runtime.validate_execution_options(opts), do: {:ok, opts}
  end

  defp persistence(jido) do
    case Jido.Persistence.resolve_config(:inherit, jido) do
      {:ok, nil} ->
        invalid("durable execution requires a persistence adapter", %{instance: jido})

      {:ok, config} ->
        {:ok, config}

      {:error, _reason} = error ->
        error
    end
  end

  defp validate_ref_instance(jido, %Ref{namespace: namespace}) do
    if Jido.Instance.NamespaceRegistry.namespace(jido) == namespace,
      do: :ok,
      else: invalid("durable reference does not belong to this Jido instance", %{namespace: namespace})
  end

  defp validate_options(opts, allowed) do
    cond do
      not Keyword.keyword?(opts) ->
        invalid("durable options must be a keyword list", %{options: opts})

      Keyword.keys(opts) != Enum.uniq(Keyword.keys(opts)) ->
        invalid("durable option keys must be unique", %{options: opts})

      Keyword.keys(opts) -- allowed != [] ->
        invalid("durable options contain unsupported keys", %{
          unsupported: Keyword.keys(opts) -- allowed
        })

      not valid_timeout?(Keyword.get(opts, :operation_timeout, :infinity)) ->
        invalid("durable operation_timeout is invalid", %{timeout: opts[:operation_timeout]})

      not valid_now?(Keyword.get(opts, :now, 0)) ->
        invalid("durable now is invalid", %{now: opts[:now]})

      true ->
        :ok
    end
  end

  defp valid_timeout?(:infinity), do: true
  defp valid_timeout?(timeout), do: is_integer(timeout) and timeout >= 0
  defp valid_now?(now), do: is_integer(now) and now >= 0
  defp timeout_value(:infinity), do: :infinity
  defp timeout_value(timeout), do: timeout

  defp now_option(opts), do: if(Keyword.has_key?(opts, :now), do: [now: opts[:now]], else: [])

  defp active?(jido, ref) do
    runner = Jido.Instance.Names.exec_runner(jido)
    id = Ref.execution_id(ref)

    case Runic.Runner.admission_status(runner, id) do
      {:ok, %{active_units: count}} when count > 0 -> true
      _other -> false
    end
  end

  defp invalid(message, details),
    do:
      {:error,
       Jido.Error.validation_error(message,
         kind: :config,
         subject: __MODULE__,
         details: details
       )}

  defp invalid_ref(), do: invalid("durable execution reference is invalid", %{})
end
