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

  Each execution reference admits one direct operation at a time. A competing
  operation returns `{:error, :execution_busy}` and can retry later.
  Set `:operation_timeout` in milliseconds to limit the operation. The
  default is `:infinity`. An in-progress storage call and worker cleanup can
  finish after expiry. A timeout stops the worker and leaves the last
  confirmed checkpoint available for retry.

  Timed waits expose `Jido.Durable.Status.next_wake_at`. A host can call
  `resume/3` at or after that UTC Unix time. A cron host calculates an
  occurrence and delivers it as a Signal; Durable does not own a scheduler.
  """

  alias Jido.Durable.{Execution, Operation, Ref, Runtime, Status}
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
         {:ok, ref} <- Ref.new(jido, Keyword.get(opts, :id, signal.id)) do
      Operation.with_owner(ref, opts, fn deadline ->
        with {:ok, params} <- signal_params(signal),
             {:ok, context} <- durable_context(signal, Keyword.get(opts, :context, %{})),
             {:ok, exec_opts} <- exec_options(Keyword.get(opts, :exec_opts, [])),
             {:ok, instruction} <- durable_instruction(target, params, context),
             {:ok, execution} <- Execution.new(ref, instruction, signal, context, exec_opts),
             :ok <- Runtime.register(jido, Ref.execution_id(ref), config),
             :ok <- save_execution(jido, execution) do
          Operation.execute(jido, execution, config, opts, deadline)
        end
      end)
    end
  end

  def start(_jido, _target, _signal, _opts),
    do: {:error, Jido.Error.validation_error("durable input must be a Jido.Signal")}

  @doc "Resumes a stored execution and runs until its next durable stop."
  @spec resume(atom(), Ref.t(), keyword()) :: operation_result()
  def resume(jido, ref, opts \\ [])

  def resume(jido, %Ref{} = ref, opts) do
    with :ok <- validate_options(opts, @resume_option_keys),
         :ok <- validate_ref_instance(jido, ref),
         {:ok, config} <- persistence(jido) do
      Operation.with_owner(ref, opts, fn deadline ->
        with {:ok, execution} <- load_execution(config, ref),
             do: Operation.execute(jido, execution, config, opts, deadline)
      end)
    end
  end

  def resume(_jido, _ref, _opts), do: invalid_ref()

  @doc "Saves one Signal for an addressed wait and continues the durable Flow."
  @spec signal(atom(), Ref.t(), Jido.Exec.Wait.id(), Signal.t(), keyword()) ::
          operation_result()
  def signal(jido, ref, wait_id, signal, opts \\ [])

  def signal(jido, %Ref{} = ref, wait_id, %Signal{} = signal, opts) do
    with :ok <- validate_options(opts, @signal_option_keys),
         :ok <- validate_ref_instance(jido, ref),
         {:ok, config} <- persistence(jido) do
      Operation.with_owner(ref, opts, fn deadline ->
        with {:ok, execution} <- load_execution(config, ref),
             {:ok, input} <- Jido.Exec.Wait.input(wait_id, signal),
             :ok <- Runtime.accept_input(jido, Ref.execution_id(ref), config, input, now_option(opts)) do
          Operation.execute(jido, execution, config, opts, deadline)
        else
          {:rejected, reason} -> {:error, reason}
          error -> error
        end
      end)
    end
  end

  def signal(_jido, _ref, _wait_id, _signal, _opts),
    do: {:error, Jido.Error.validation_error("durable wait input must be a Jido.Signal")}

  @doc "Reads the last committed durable execution status."
  @spec status(atom(), Ref.t()) :: operation_result()
  def status(jido, %Ref{} = ref) do
    with {:ok, workflow} <- read_checkpoint(jido, ref) do
      {:ok, Status.new(ref, workflow, active?(jido, ref))}
    end
  end

  def status(_jido, _ref), do: invalid_ref()

  @doc "Reads the normal `Jido.Exec` result from the last committed state."
  @spec result(atom(), Ref.t()) :: Jido.Exec.exec_result()
  def result(jido, %Ref{} = ref) do
    with {:ok, workflow} <- read_checkpoint(jido, ref) do
      Jido.Exec.Result.project(workflow)
    end
  end

  def result(_jido, _ref), do: invalid_ref()

  defp read_checkpoint(jido, ref) do
    with :ok <- validate_ref_instance(jido, ref),
         {:ok, config} <- persistence(jido),
         {:ok, _execution} <- load_execution(config, ref),
         do: ContinuationStore.read_workflow(config, Ref.execution_id(ref))
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

  defp load_execution(config, %Ref{} = ref) do
    id = Ref.execution_id(ref)

    with {:ok, %Execution{} = execution} <- ContinuationStore.read_fact(config, id, @metadata_fact),
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
         %Jido.Instruction{kind: :flow} = instruction <- instruction,
         :ok <- ExecRuntime.portable(instruction) do
      {:ok, instruction}
    else
      %Jido.Instruction{} ->
        invalid("durable execution requires a Flow", %{target: target})

      error ->
        error
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

      not Operation.valid_timeout?(Keyword.get(opts, :operation_timeout, :infinity)) ->
        invalid("durable operation_timeout is invalid", %{timeout: opts[:operation_timeout]})

      not valid_now?(Keyword.get(opts, :now, 0)) ->
        invalid("durable now is invalid", %{now: opts[:now]})

      true ->
        :ok
    end
  end

  defp valid_now?(now), do: is_integer(now) and now >= 0

  defp now_option(opts), do: if(Keyword.has_key?(opts, :now), do: [now: opts[:now]], else: [])

  defp active?(jido, ref) do
    runner = Jido.Instance.Names.exec_runner(jido)
    id = Ref.execution_id(ref)

    case Runic.Runner.admission_status(runner, id) do
      {:ok, %{active_units: count}} when count > 0 -> true
      _other -> false
    end
  catch
    :exit, _reason -> false
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
