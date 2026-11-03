defmodule Jido.AgentServer.DurableTurn do
  @moduledoc false

  alias __MODULE__.{CheckpointStore, WaitHost}
  alias Runic.Runner
  alias Jido.Exec.{Continuation, Runtime}

  def instruction(prepared),
    do: Jido.Instruction.resolve(prepared.turn.executable, prepared.turn.input, prepared.context)

  def accept(data, prepared) do
    with {:ok, instruction} <- flow_instruction(prepared),
         {:ok, _} <- validate_input(instruction),
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
             expires_at: expires_at(data.active)
           })
  end

  def restore(agent, receipt, context, specs) do
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
         {:ok, instruction} <- flow_instruction(prepared),
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
         do: validate_receipt(data, receipt)
  end

  def release_handoff(data, receipt, prepared) do
    with {:ok, released} <-
           Continuation.release_handoff(receipt, %{
             expires_at: expires_at(data.active),
             admitted_signal: prepared.signal,
             plugin_inputs: prepared.context.plugin_inputs
           }),
         do: validate_receipt(data, released)
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

  def validate_restore(agent, %{status: status} = receipt) when status in [:running, :released] do
    with {:ok, specs} <- Jido.Plugin.Normalizer.normalize_all(Jido.Agent.runtime_plugins(agent)),
         {:ok, _prepared} <-
           if(status == :running,
             do: restore(agent, receipt, receipt.context, specs),
             else: restore_handoff(agent, receipt, receipt.context, specs)
           ),
         do: :ok
  end

  def validate_restore(_agent, _receipt), do: :ok

  def identity(data),
    do: {:jido_execution, Jido.namespace(data.jido), data.partition, data.agent.id, data.active.turn_id}

  def start(data, owner, hooks, policy) do
    id = identity(data)
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

    with :ok <- stop_existing(data.runner, id),
         {:ok, instruction} <- instruction(data.active.prepared),
         {:ok, workflow} <- Jido.Exec.compile(%{instruction | context: %{}}),
         :ok <- CheckpointStore.register(data.jido, id, data.persistence, owner),
         {:ok, saved} <-
           CheckpointStore.update_workflow(data.jido, id, &WaitHost.resolve(&1, now())),
         options =
           Keyword.put(options, :run_context, %{
             _global: WaitHost.context(data.active.prepared.context, id, saved)
           }) do
      if saved && not Runic.Workflow.is_runnable?(saved) && Runtime.pending_waits(saved) != [] do
        waiting(saved)
      else
        with {:ok, worker} <-
               resume_or_start(
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

  defp resume_or_start(runner, id, workflow, instruction, options, activation_state) do
    case Runner.resume(runner, id, options) do
      {:error, {:unsupported_batch_rehydration, :hybrid}} ->
        resume_or_start(
          runner,
          id,
          workflow,
          instruction,
          Keyword.put(options, :rehydration, :full),
          activation_state
        )

      {:error, :not_found} ->
        with {:ok, input} <- validate_input(instruction),
             {:ok, worker} <-
               Runner.start_workflow(
                 runner,
                 id,
                 Runic.Workflow.enable_event_emission(workflow),
                 options
               ),
             :ok <-
               Jido.AgentServer.Supervisor.remember_execution(
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

  defp stop_existing(runner, id) do
    if Runner.lookup(runner, id), do: Runner.cancel(runner, id), else: :ok
  end

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

  def suspend(runner, id), do: Runner.stop(runner, id, persist: false)

  def deliver(data, input) do
    id = data.active.worker_id

    # Acceptance is saved independently of consumption. Recovery can consume
    # it even if the acknowledgement or the next save is lost.
    case CheckpointStore.update_workflow(data.jido, id, fn workflow ->
           case WaitHost.accept(workflow, input, now()) do
             {:ok, next} -> {:ok, next}
             {:error, reason} -> {:rejected, reason}
           end
         end) do
      {:ok, %Runic.Workflow{}} -> :ok
      {:ok, nil} -> {:error, :missing_wait_checkpoint}
      result -> result
    end
  end

  defp waiting(workflow),
    do: {:waiting, Runtime.pending_waits(workflow), Runtime.next_wait_deadline(workflow)}

  defp now, do: System.system_time(:millisecond)

  defp portable_facts(workflow) do
    if Enum.all?(Runic.Workflow.facts(workflow), fn fact ->
         Jido.Codec.Term.valid?(Jido.Exec.Fact.value(fact))
       end), do: :ok, else: {:error, :non_portable_flow_output}
  end

  defp flow_instruction(%{turn: %{execution_mode: :durable}} = prepared) do
    case instruction(prepared) do
      {:ok, %{kind: :flow} = instruction} -> {:ok, instruction}
      {:ok, _instruction} -> {:error, :not_durable_flow}
      error -> error
    end
  end

  defp flow_instruction(_prepared), do: {:error, :not_durable_flow}

  defp validate_input(instruction),
    do:
      Jido.Exec.Validation.input(instruction.target, instruction.params, %{
        phase: :flow_input
      })

  defp expires_at(%{deadline: :infinity}), do: :infinity

  defp expires_at(%{deadline: deadline}) do
    System.system_time(:millisecond) +
      max(0, deadline - System.monotonic_time(:millisecond))
  end

  defp validate_receipt(%{persistence: persistence}, receipt)
       when persistence in [nil, false],
       do: {:ok, receipt}

  defp validate_receipt(_data, receipt) do
    with :ok <- Jido.Codec.Term.validate(receipt, :server_turn), do: {:ok, receipt}
  end
end
