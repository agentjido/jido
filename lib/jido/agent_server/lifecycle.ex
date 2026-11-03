defmodule Jido.AgentServer.Lifecycle do
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
    idle_policy: :stop,
    plugin_runtime_options: []
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
  @wait_input_limit 1_024

  require Logger

  alias Jido.Agent.Validation
  alias Jido.AgentServer.Supervisor, as: ServerSupervisor
  alias Jido.Exec.{Continuation, Runtime, Wait}
  alias Jido.Persistence.ContinuationStore
  alias Jido.Trace.Context, as: TraceContext
  alias Runic.Runner
  alias Runic.Workflow
  alias Runic.Workflow.{CausalContext, Fact, Runnable}
  alias Runic.Workflow.Events.FactProduced

  def max_timeout, do: @max_timeout
  def runtime_defaults, do: @runtime_defaults
  def runtime_keys, do: @runtime_keys
  def startup_keys, do: @startup_keys

  def unique_keyword?(value) do
    is_list(value) and Keyword.keyword?(value) and
      Keyword.keys(value) == Enum.uniq(Keyword.keys(value))
  end

  def with_turn_timeout(opts) do
    if Keyword.has_key?(opts, :turn_timeout) do
      {:ok, opts}
    else
      config = Application.get_env(:jido, Jido.AgentServer, [])

      cond do
        not is_list(config) or not Keyword.keyword?(config) ->
          invalid_options("AgentServer application configuration must be a keyword list")

        not unique_keyword?(config) ->
          invalid_options("AgentServer application configuration keys must be unique")

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
         :ok <-
           Jido.Plugin.Normalizer.validate_runtime_options(opts[:plugin_runtime_options]),
         :ok <-
           validate_setting(
             is_integer(opts[:debug_max_events]) and opts[:debug_max_events] in 1..10_000,
             :debug_max_events
           ),
         :ok <- validate_timeout(opts, :persistence_timeout),
         :ok <- validate_setting(opts[:persistence_mode] in [:create, :restore], :persistence_mode),
         do:
           validate_setting(
             opts[:idle_policy] != :hibernate or persistence_enabled?(opts[:persistence]),
             :idle_policy
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
    if unique_keyword?(opts) and Keyword.keys(opts) -- [:active, :timeout] == [] do
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
    if unique_keyword?(opts) and Keyword.keys(opts) -- allowed == [] do
      with {:ok, context} <- Validation.normalize_context(Keyword.get(opts, :context)),
           :ok <- Validation.validate_caller_context(context) do
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
      retry_if: {Jido.Error, :retryable?, []}
    }
  end

  def execution_hooks(hooks, trace) do
    hooks = Enum.map(hooks, fn {name, fun} -> {name, safe_hook(name, fun)} end)
    dispatch = Keyword.get(hooks, :on_dispatch)
    failed = Keyword.get(hooks, :on_failed)

    hooks
    |> Keyword.put(:on_dispatch, fn runnable, state ->
      Logger.metadata(if trace, do: Map.to_list(Jido.Trace.telemetry_context(trace)), else: [])
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
    outcome = %{
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

    handoff_chain? =
      case active do
        %{chain_order: order} when order > 0 -> true
        _ -> match?({:handoff, _, %Jido.Instruction{}, _}, Map.get(active, :result))
      end

    if handoff_chain? do
      Map.merge(outcome, %{chain_id: active.chain_id, chain_order: active.chain_order})
    else
      outcome
    end
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

  def start(data, mode) do
    with :ok <- ServerSupervisor.close_execution(data.activation_state),
         {:ok, config} <- Jido.Persistence.resolve_config(data.persistence, data.jido),
         {:ok, agent, revision, turn} <-
           Jido.Persistence.open_agent(config, data.agent, mode, persistence_options(data)),
         {:ok, agent} <- Validation.validate_instance(agent),
         {:ok, revision, turn} <- settle_unreleased_handoff(data, config, agent, revision, turn),
         :ok <- validate_continuation(agent, turn) do
      {:ok, agent, revision, config, turn}
    end
  end

  def save(data, agent, revision, expected_revision, server_turn) do
    Jido.Persistence.save_agent(
      data.persistence,
      agent,
      persistence_options(data) ++
        [
          revision: revision,
          expected_revision: expected_revision,
          server_turn: server_turn
        ]
    )
  end

  def write_result(result, deadline) do
    if System.monotonic_time(:millisecond) >= deadline,
      do: {:error, :indeterminate},
      else: result
  end

  def resumable?(reason),
    do: reason not in [:conflict, :indeterminate] and not match?({:indeterminate, _}, reason)

  def error(reason, resumable?), do: {:error, %{reason: reason, resumable?: resumable?}}

  def snapshot(agent, revision), do: %{agent: agent, state_version: revision}

  def upgrade(agent, action, context) do
    with {:ok, snapshot} <- Jido.Persistence.snapshot(agent, context: context),
         do: Jido.Persistence.upgrade(snapshot, action, context: context)
  end

  @doc false
  def persistence_mode(state, requested) do
    lifetime = :ets.lookup_element(state, :durable_lifetime, 2)

    if :atomics.get(lifetime, 1) == 1 or not :ets.insert_new(state, {:durable_started, true}),
      do: :restore,
      else: requested
  end

  @doc false
  def restore(state, agent, revision) do
    # The parent child specification retains this reference across root loss.
    # A separate start has a new reference and still enforces strict :create.
    lifetime = :ets.lookup_element(state, :durable_lifetime, 2)
    :atomics.put(lifetime, 1, 1)
    :ets.insert(state, {:checkpoint, agent, revision})
  end

  def durable_instruction(prepared),
    do: Jido.Instruction.resolve(prepared.turn.executable, prepared.turn.input, prepared.context)

  def accept_continuation(data, prepared) do
    with {:ok, instruction} <- durable_flow_instruction(prepared),
         {:ok, _} <- validate_flow_input(instruction),
         do:
           Continuation.running(%{
             id: data.active.turn_id,
             signal: data.active.source_signal,
             admitted_signal: prepared.signal,
             context:
               Map.drop(prepared.context, [
                 :agent_id,
                 :agent_module,
                 :agent_signal_source,
                 :agent_state,
                 :agent_topology,
                 :plugin_inputs,
                 :signal,
                 :turn_id,
                 :trace_context
               ]),
             plugin_inputs: prepared.context.plugin_inputs,
             target: instruction.target,
             expires_at: continuation_expiry(data.active)
           })
  end

  def restore_continuation(agent, receipt, context, specs) do
    with {:ok, command} <-
           Jido.AgentServer.Command.new_trusted_agent(agent, receipt.admitted_signal, context),
         command = %{command | plugin_inputs: receipt.plugin_inputs},
         {:ok, prepared} <-
           Jido.Agent.Runner.prepare_admitted(
             command,
             receipt.signal,
             [],
             specs
           ),
         {:ok, instruction} <- durable_flow_instruction(prepared),
         :ok <- Continuation.compatible(receipt, instruction),
         do: {:ok, prepared}
  end

  def accept_handoff(data, %Jido.Instruction{} = instruction) do
    with {:ok, receipt} <-
           Continuation.accept_handoff(%{
             id: data.active.handoff_id,
             signal: data.active.source_signal,
             context: data.active.turn_context,
             instruction: instruction,
             chain_id: data.active.chain_id,
             chain_order: data.active.chain_order + 1,
             predecessor_id: data.active.turn_id
           }),
         do: validate_continuation_receipt(data, receipt)
  end

  def release_handoff(data, receipt, prepared) do
    with {:ok, released} <-
           Continuation.release_handoff(receipt, %{
             expires_at: continuation_expiry(data.active),
             admitted_signal: prepared.signal,
             plugin_inputs: prepared.context.plugin_inputs
           }),
         do: validate_continuation_receipt(data, released)
  end

  def restore_handoff(agent, receipt, context, specs) do
    with {:ok, command} <-
           Jido.AgentServer.Command.new_trusted_agent(agent, receipt.admitted_signal, context),
         command = %{command | plugin_inputs: receipt.plugin_inputs},
         {:ok, prepared} <-
           Jido.Agent.Runner.prepare_admitted_handoff(
             command,
             receipt.signal,
             receipt.instruction,
             [],
             specs
           ),
         :ok <- Continuation.compatible(receipt, receipt.instruction) do
      {:ok, prepared}
    end
  end

  def validate_continuation(agent, %{status: status} = receipt)
      when status in [:running, :released] do
    with {:ok, specs} <- Jido.Plugin.Normalizer.normalize_all(Jido.Agent.runtime_plugins(agent)),
         {:ok, _prepared} <-
           if(status == :running,
             do: restore_continuation(agent, receipt, receipt.context, specs),
             else: restore_handoff(agent, receipt, receipt.context, specs)
           ),
         do: :ok
  end

  def validate_continuation(_agent, _receipt), do: :ok

  def execution_identity(data),
    do: {:jido_execution, Jido.namespace(data.jido), data.partition, data.agent.id, data.active.turn_id}

  def start_execution(data, owner, hooks, policy) do
    id = execution_identity(data)
    notify = fn _ -> send(owner, {:durable_advance, data.active.turn_id}) end

    user_complete = hooks[:on_complete]
    user_failed = hooks[:on_failed]
    user_idle = hooks[:on_idle]

    options = [
      owner: owner,
      dispatch_mode: :manual,
      checkpoint_strategy: :manual,
      rehydration: :hybrid,
      scheduler_policies: [{:default, policy}],
      hooks:
        hooks
        |> Keyword.put(:on_complete, fn runnable, result, state ->
          if user_complete, do: user_complete.(runnable, result, state)
          notify.(nil)
        end)
        |> Keyword.put(:on_failed, fn runnable, error, state ->
          if user_failed, do: user_failed.(runnable, error, state)
          notify.(nil)
        end)
        |> Keyword.put(:on_idle, fn state ->
          if user_idle, do: user_idle.(state)
          notify.(state)
        end)
    ]

    with :ok <- stop_existing_execution(data.runner, id),
         {:ok, instruction} <- durable_instruction(data.active.prepared),
         {:ok, workflow} <- Jido.Exec.compile(%{instruction | context: %{}}),
         :ok <- ContinuationStore.register(data.jido, id, data.persistence, owner),
         {:ok, saved} <-
           ContinuationStore.update_workflow(data.jido, id, &resolve_wait_inputs(&1, now())),
         options =
           Keyword.put(options, :run_context, %{
             _global: wait_context(data.active.prepared.context, id, saved)
           }) do
      if saved && not Workflow.is_runnable?(saved) && Runtime.pending_waits(saved) != [] do
        waiting(saved)
      else
        with {:ok, worker} <-
               resume_or_start_execution(
                 data.runner,
                 id,
                 workflow,
                 instruction,
                 options,
                 data.activation_state
               ),
             do: {:ok, worker, id}
      end
    end
  end

  def advance_execution(runner, id) do
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
          # A native task can finish between get_workflow and step. Confirm
          # the quiescent graph rather than the earlier active snapshot.
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

  def suspend_execution(runner, id), do: Runner.stop(runner, id, persist: false)

  def deliver_wait_input(data, input) do
    id = data.active.worker_id

    # Acceptance is saved independently of consumption. Recovery can consume
    # it even if the acknowledgement or the next save is lost.
    case ContinuationStore.update_workflow(data.jido, id, fn workflow ->
           case accept_wait_input(workflow, input, now()) do
             {:ok, next} -> {:ok, next}
             {:error, reason} -> {:rejected, reason}
           end
         end) do
      {:ok, %Workflow{}} -> :ok
      {:ok, nil} -> {:error, :missing_wait_checkpoint}
      result -> result
    end
  end

  def wait_context(context, execution_id, workflow) do
    floor = acceptance_time(workflow, System.system_time(:millisecond))

    context
    |> Runtime.context(true)
    |> Runtime.wait_context(execution_id, fn -> max(System.system_time(:millisecond), floor) end)
  end

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

  def invalid_options(message),
    do: {:error, Jido.Error.validation_error(message, kind: :config)}

  defp resume_or_start_execution(runner, id, workflow, instruction, options, activation_state) do
    case Runner.resume(runner, id, options) do
      {:error, {:unsupported_batch_rehydration, :hybrid}} ->
        resume_or_start_execution(
          runner,
          id,
          workflow,
          instruction,
          Keyword.put(options, :rehydration, :full),
          activation_state
        )

      {:error, :not_found} ->
        with {:ok, input} <- validate_flow_input(instruction),
             {:ok, worker} <-
               Runner.start_workflow(
                 runner,
                 id,
                 Workflow.enable_event_emission(workflow),
                 options
               ),
             :ok <-
               ServerSupervisor.remember_execution(
                 activation_state,
                 runner,
                 id,
                 worker
               ),
             {:ok, _} <-
               Runner.start_execution(
                 runner,
                 id,
                 Jido.Exec.Fact.local_value(Jido.Exec.Frame.new(input)),
                 run_context: options[:run_context],
                 scheduler_policies: options[:scheduler_policies]
               ),
             :ok <- Runner.checkpoint(runner, id),
             do: {:ok, worker}

      result ->
        result
    end
  end

  defp stop_existing_execution(runner, id) do
    if Runner.lookup(runner, id), do: Runner.cancel(runner, id), else: :ok
  end

  defp waiting(workflow),
    do: {:waiting, Runtime.pending_waits(workflow), Runtime.next_wait_deadline(workflow)}

  defp now, do: System.system_time(:millisecond)

  defp portable_facts(workflow) do
    if Enum.all?(Workflow.facts(workflow), fn fact ->
         Jido.Codec.Term.valid?(Jido.Exec.Fact.value(fact))
       end),
       do: :ok,
       else: {:error, :non_portable_flow_output}
  end

  defp durable_flow_instruction(%{turn: %{execution_mode: :durable}} = prepared) do
    case durable_instruction(prepared) do
      {:ok, %{kind: :flow} = instruction} -> {:ok, instruction}
      {:ok, _instruction} -> {:error, :not_durable_flow}
      error -> error
    end
  end

  defp durable_flow_instruction(_prepared), do: {:error, :not_durable_flow}

  defp validate_flow_input(instruction),
    do:
      Jido.Exec.Validation.input(instruction.target, instruction.params, %{
        phase: :flow_input
      })

  defp continuation_expiry(%{deadline: :infinity}), do: :infinity

  defp continuation_expiry(%{deadline: deadline}) do
    System.system_time(:millisecond) +
      max(0, deadline - System.monotonic_time(:millisecond))
  end

  defp validate_continuation_receipt(%{persistence: persistence}, receipt)
       when persistence in [nil, false],
       do: {:ok, receipt}

  defp validate_continuation_receipt(_data, receipt) do
    with :ok <- Jido.Codec.Term.validate(receipt, :server_turn), do: {:ok, receipt}
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

  # Host receipts share the native log so the existing conditional checkpoint
  # write saves both host acceptance and Flow progress atomically.
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

  defp wait_error(reason),
    do: {:error, Jido.Error.config_error("wait host rejected operation", %{reason: reason})}

  # An accepted Handoff proves that the predecessor commit is durable. It does
  # not prove that predecessor effects finished. Recovery must not replay those
  # effects or start the successor across that uncertain boundary.
  defp settle_unreleased_handoff(data, config, agent, revision, %{status: :accepted} = turn) do
    failed = Continuation.put_status!(turn, :failed)
    runtime = %{data | persistence: config}

    with :ok <- save(runtime, agent, revision + 1, revision, failed),
         do: {:ok, revision + 1, failed}
  end

  defp settle_unreleased_handoff(_data, _config, _agent, revision, turn),
    do: {:ok, revision, turn}

  defp persistence_options(data), do: [instance: data.jido, partition: data.partition]
  defp persistence_enabled?(source), do: source not in [nil, false]

  defp validate_exec(opts) do
    if unique_keyword?(opts) and Keyword.keys(opts) -- @exec_keys == [] and
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
    unique_keyword?(hooks) and
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
