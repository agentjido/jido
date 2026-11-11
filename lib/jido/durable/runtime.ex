defmodule Jido.Durable.Runtime do
  @moduledoc false

  @wait_input_limit 1_024
  alias Jido.Exec.{Runtime, Wait}
  alias Jido.Persistence.ContinuationStore
  alias Runic.Runner
  alias Runic.Workflow
  alias Runic.Workflow.{CausalContext, Fact, Runnable}
  alias Runic.Workflow.Events.FactProduced

  @doc false
  def open(runner, id, instruction, context, opts) do
    instance = Keyword.fetch!(opts, :instance)
    persistence = Keyword.fetch!(opts, :persistence)
    owner = Keyword.get(opts, :owner, self())
    hooks = Keyword.get(opts, :hooks, [])
    policy = Keyword.fetch!(opts, :policy)
    now = Keyword.get(opts, :now, now())
    max_concurrency = Keyword.get(opts, :max_concurrency, 1)
    on_started = Keyword.get(opts, :on_started, fn _worker -> :ok end)
    notify = Keyword.get(opts, :notify, fn -> send(owner, {:jido_durable_advance, id}) end)

    options = [
      owner: owner,
      dispatch_mode: :manual,
      checkpoint_strategy: :manual,
      rehydration: :hybrid,
      scheduler_policies: [{:default, policy}],
      hooks: notifying_hooks(hooks, notify)
    ]

    with :ok <- validate_now(now),
         :ok <- stop_existing_execution(runner, id),
         {:ok, workflow} <- Jido.Exec.compile(%{instruction | context: %{}}, []),
         :ok <- ContinuationStore.register(instance, id, persistence, owner),
         {:ok, saved} <-
           ContinuationStore.update_workflow(instance, id, &resolve_wait_inputs(&1, now)),
         options =
           Keyword.put(options, :run_context, %{
             _global: wait_context(context, id, saved, now, max_concurrency)
           }) do
      if saved && not Workflow.is_runnable?(saved) && Runtime.pending_waits(saved) != [] do
        waiting(saved)
      else
        with {:ok, worker} <-
               resume_or_start_execution(
                 runner,
                 id,
                 workflow,
                 instruction,
                 options,
                 on_started
               ) do
          {:ok, worker, id}
        end
      end
    end
  end

  @doc false
  def advance(runner, id) do
    # No step can start before the preceding graph has a confirmed save.
    with {:ok, workflow} <- Runner.get_workflow(runner, id),
         :ok <- portable_facts(workflow),
         :ok <- Runner.checkpoint(runner, id) do
      case Runner.step(runner, id) do
        :ok ->
          :running

        {:error, :busy} ->
          :running

        {:error, :not_runnable} ->
          # Native work can finish between the read and the step. Confirm and
          # save the settled graph instead of using the earlier active view.
          with {:ok, settled} <- Runner.get_workflow(runner, id),
               :ok <- portable_facts(settled),
               :ok <- Runner.checkpoint(runner, id) do
            if Runtime.pending_waits(settled) == [], do: :complete, else: waiting(settled)
          end

        {:error, :admission_stopped} ->
          :complete

        error ->
          error
      end
    end
  end

  @doc false
  def suspend(runner, id) do
    case Runner.stop(runner, id, persist: false) do
      :ok -> :ok
      {:error, :not_found} -> :ok
      error -> error
    end
  end

  @doc false
  def register(instance, id, persistence, owner \\ self()),
    do: ContinuationStore.register(instance, id, persistence, owner)

  @doc false
  def workflow(instance, id, persistence, owner \\ self()) do
    with :ok <- register(instance, id, persistence, owner) do
      ContinuationStore.update_workflow(instance, id, &{:ok, &1})
    end
  end

  @doc false
  def accept_input(instance, id, persistence, input, opts \\ []) do
    owner = Keyword.get(opts, :owner, self())
    now = Keyword.get(opts, :now, now())

    with :ok <- validate_now(now),
         :ok <- register(instance, id, persistence, owner) do
      case ContinuationStore.update_workflow(instance, id, fn workflow ->
             case accept_wait_input(workflow, input, now) do
               {:ok, next} -> {:ok, next}
               {:error, reason} -> {:rejected, reason}
             end
           end) do
        {:ok, %Workflow{}} -> :ok
        {:ok, nil} -> {:error, :missing_wait_checkpoint}
        result -> result
      end
    end
  end

  @doc false
  def wait_context(context, execution_id, workflow) do
    wait_context(context, execution_id, workflow, now())
  end

  @doc false
  def wait_context(context, execution_id, workflow, now, max_concurrency \\ 1) do
    floor = acceptance_time(workflow, now)

    context
    |> Runtime.caller_context()
    |> Map.put(:__jido_exec_max_concurrency__, max_concurrency)
    |> Runtime.wait_context(execution_id, fn -> max(now, floor) end)
  end

  @doc false
  def accept_wait_input(workflow, input, now) do
    with :ok <- Wait.validate_input(input, now) do
      receipts = wait_inputs(workflow)

      case Enum.find(receipts, &(&1.input.id == input.id)) do
        %{input: ^input} -> {:ok, workflow}
        %{} -> wait_error(:conflicting_input_id)
        nil -> accept_new_wait_input(workflow, input, now, receipts)
      end
    end
  end

  @doc false
  def resolve_wait_inputs(nil, _now), do: {:ok, nil}

  def resolve_wait_inputs(workflow, now) when is_integer(now) and now >= 0 do
    receipts = wait_inputs(workflow)
    now = acceptance_time(workflow, now)

    Enum.reduce_while(Runtime.pending_waits(workflow), {:ok, workflow}, fn request, {:ok, current} ->
      candidates = Enum.filter(receipts, &(&1.input.wait_id == request.id))

      case Runtime.resolve_wait(current, request.id, candidates, now) do
        {:error, _reason} = error -> {:halt, error}
        result -> {:cont, result}
      end
    end)
  end

  def resolve_wait_inputs(_workflow, _now), do: wait_error(:invalid_clock)

  @doc false
  def validate_execution_options(opts) do
    case Runtime.execution_options(opts, durable_policy_defaults()) do
      {:ok, _policy, _max_concurrency} -> :ok
      {:error, error} -> option_error(Exception.message(error), opts)
    end
  end

  @doc false
  def execution_policy(opts) do
    {:ok, policy} = Runtime.execution_policy(opts, durable_policy_defaults())
    policy
  end

  defp durable_policy_defaults,
    do: [base_delay_ms: 500, max_delay_ms: 30_000, max_concurrency: 1]

  defp notifying_hooks(hooks, notify) do
    user_complete = hooks[:on_complete]
    user_failed = hooks[:on_failed]
    user_idle = hooks[:on_idle]

    hooks
    |> Keyword.put(:on_complete, fn runnable, result, state ->
      if user_complete, do: user_complete.(runnable, result, state)
      notify.()
    end)
    |> Keyword.put(:on_failed, fn runnable, error, state ->
      if user_failed, do: user_failed.(runnable, error, state)
      notify.()
    end)
    |> Keyword.put(:on_idle, fn state ->
      if user_idle, do: user_idle.(state)
      notify.()
    end)
  end

  defp resume_or_start_execution(runner, id, workflow, instruction, options, on_started) do
    case Runner.resume(runner, id, options) do
      {:error, {:unsupported_batch_rehydration, :hybrid}} ->
        resume_or_start_execution(
          runner,
          id,
          workflow,
          instruction,
          Keyword.put(options, :rehydration, :full),
          on_started
        )

      {:error, :not_found} ->
        with {:ok, worker} <-
               Runner.start_workflow(
                 runner,
                 id,
                 Workflow.enable_event_emission(workflow),
                 options
               ),
             :ok <- on_started.(worker),
             {:ok, _} <-
               Runner.start_execution(
                 runner,
                 id,
                 Jido.Exec.Fact.local_value(execution_input(instruction)),
                 run_context: options[:run_context],
                 scheduler_policies: options[:scheduler_policies]
               ),
             :ok <- Runner.checkpoint(runner, id) do
          {:ok, worker}
        end

      result ->
        result
    end
  end

  defp stop_existing_execution(runner, id) do
    if Runner.lookup(runner, id), do: Runner.cancel(runner, id), else: :ok
  end

  defp execution_input(%Jido.Instruction{params: params}), do: params

  defp waiting(workflow),
    do: {:waiting, Runtime.pending_waits(workflow), Runtime.next_wait_deadline(workflow)}

  defp portable_facts(workflow) do
    if Enum.all?(Workflow.facts(workflow), fn fact ->
         Jido.Codec.Term.valid?(Jido.Exec.Fact.value(fact))
       end),
       do: :ok,
       else: {:error, :non_portable_flow_output}
  end

  defp accept_new_wait_input(workflow, input, now, receipts) do
    request = Enum.find(Runtime.pending_waits(workflow), &(&1.id == input.wait_id))

    cond do
      is_nil(request) ->
        wait_error(:stale_target)

      not Wait.matches?(request, input.event, input.payload) ->
        wait_error(:unmatched_input)

      length(receipts) >= @wait_input_limit ->
        wait_error(:input_limit)

      true ->
        {:ok,
         record_wait_input(workflow, %{
           type: :jido_wait_input,
           input: input,
           accepted_at: acceptance_time(workflow, now),
           order: length(receipts)
         })}
    end
  end

  # Wall-clock correction must not reorder saved acceptance. Receipt order
  # breaks ties when UTC time moves backwards or remains unchanged.
  defp acceptance_time(nil, now), do: now

  defp acceptance_time(workflow, now) do
    accepted = Enum.reduce(wait_inputs(workflow), now, &max(&1.accepted_at, &2))
    Enum.reduce(Runtime.pending_waits(workflow), accepted, &max(&1.opened_at, &2))
  end

  defp wait_inputs(workflow) do
    for %Fact{meta: %{jido_wait_record: true}, value: %{type: :jido_wait_input} = value} <-
          Workflow.facts(workflow),
        do: value
  end

  # Host receipts share the Runic log. The next conditional checkpoint saves
  # host acceptance and Flow progress through the same durable event stream.
  defp record_wait_input(workflow, value) do
    root =
      Enum.find_value(workflow.graph.vertices, fn
        {id, %Workflow.Root{}} -> id
        _ -> nil
      end)

    fact =
      Fact.new(
        value: Map.put(value, :version, 1),
        meta: %{jido_wait_record: true},
        ancestry: {root, nil}
      )

    runnable =
      root
      |> Runnable.new(Workflow.root(), fact, %CausalContext{})
      |> Runnable.complete(nil, [FactProduced.new(fact, producer_label: :state_produced)])

    Workflow.apply_runnable(workflow, runnable)
  end

  defp validate_now(now) when is_integer(now) and now >= 0, do: :ok
  defp validate_now(_now), do: wait_error(:invalid_clock)
  defp now, do: System.system_time(:millisecond)

  defp option_error(message, opts) do
    {:error,
     Jido.Error.validation_error(message,
       kind: :config,
       subject: Jido.Durable,
       details: %{exec_opts: opts}
     )}
  end

  defp wait_error(reason),
    do: {:error, Jido.Error.config_error("wait host rejected operation", %{reason: reason})}
end
