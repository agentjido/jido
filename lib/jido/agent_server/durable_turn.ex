defmodule Jido.AgentServer.DurableTurn do
  @moduledoc false

  alias Jido.AgentServer.{CheckpointStore, WaitHost}
  alias Runic.Runner
  alias Jido.Exec.Waits

  def instruction(prepared),
    do: Jido.Instruction.resolve(prepared.turn.executable, prepared.turn.input, prepared.context)

  def accept(data, prepared) do
    with {:ok, %{kind: :flow} = instruction} <- instruction(prepared),
         {:ok, _} <-
           Jido.Exec.Validation.input(instruction.target, instruction.params, %{
             phase: :flow_input
           }),
         receipt = %{
           id: data.active.turn_id,
           signal: data.active.source_signal,
           admitted_signal: prepared.signal,
           context:
             Map.drop(prepared.context, [
               :agent_id,
               :agent_state,
               :agent_topology,
               :plugin_inputs,
               :signal,
               :turn_id,
               :trace_context
             ]),
           plugin_inputs: prepared.context.plugin_inputs,
           fingerprint: fingerprint(instruction.target),
           status: :running,
           expires_at:
             if(data.turn_timeout == :infinity,
               do: :infinity,
               else:
                 System.system_time(:millisecond) +
                   max(0, data.active.deadline - System.monotonic_time(:millisecond))
             )
         },
         :ok <- Jido.PortableTerm.validate(receipt, :server_turn) do
      {:ok, receipt}
    end
  end

  def restore(agent, receipt, context, specs) do
    with {:ok, command} <-
           Jido.Agent.Command.new_trusted_agent(agent, receipt.admitted_signal, context),
         command = %{command | plugin_inputs: receipt.plugin_inputs},
         {:ok, prepared} <-
           Jido.Agent.Runner.prepare_for_server(command, receipt.signal, [], specs),
         :ok <- compatible(prepared, receipt),
         do: {:ok, prepared}
  end

  def compatible(prepared, receipt) do
    with {:ok, %{kind: :flow} = instruction} <- instruction(prepared),
         true <- fingerprint(instruction.target) == receipt.fingerprint do
      :ok
    else
      _ -> {:error, :execution_definition_changed}
    end
  end

  def identity(data),
    do:
      CheckpointStore.identity(
        %{jido: data.jido, partition: data.partition, agent_id: data.agent.id},
        data.active.turn_id
      )

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
      max_concurrency: 1,
      scheduler: Runic.Runner.Scheduler.Default,
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
         :ok <- CheckpointStore.create(data.jido, id),
         {:ok, saved} <-
           CheckpointStore.update_workflow(data.jido, id, &WaitHost.resolve(&1, now())),
         options =
           Keyword.put(options, :run_context, %{
             _global: WaitHost.context(data.active.prepared.context, id, saved)
           }) do
      if saved && not Runic.Workflow.is_runnable?(saved) && Waits.pending(saved) != [] do
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
      {:error, :not_found} ->
        with {:ok, input} <-
               Jido.Exec.Validation.input(instruction.target, instruction.params, %{
                 phase: :flow_input
               }),
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

      {:ok, worker} ->
        with :ok <-
               Jido.AgentServer.Supervisor.remember_execution(
                 activation_state,
                 runner,
                 id,
                 worker
               ),
             do: {:ok, worker}

      error ->
        error
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
            if Waits.pending(settled) == [], do: :complete, else: waiting(settled)
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
    do: {:waiting, Waits.pending(workflow), Waits.next_deadline(workflow)}

  defp now, do: System.system_time(:millisecond)

  defp portable_facts(workflow) do
    if Enum.all?(Runic.Workflow.facts(workflow), fn fact ->
         Jido.PortableTerm.valid?(Jido.Exec.Fact.value(fact))
       end), do: :ok, else: {:error, :non_portable_flow_output}
  end

  def fingerprint(target) do
    flow = if is_atom(target), do: target.flow(), else: target
    versions = versions({:flow, target}, %{}) |> Enum.sort()

    :sha256
    |> :crypto.hash(:erlang.term_to_binary({flow, versions}, [:deterministic]))
    |> Base.encode16(case: :lower)
  end

  defp versions({kind, module}, acc) when kind in [:action, :flow] and is_atom(module) do
    if Map.has_key?(acc, module) do
      acc
    else
      Code.ensure_loaded!(module)
      acc = Map.put(acc, module, module.module_info(:md5))
      if kind == :flow, do: versions({:flow, module.flow()}, acc), else: acc
    end
  end

  defp versions({:flow, %Jido.Flow{} = flow}, acc),
    do:
      Enum.reduce(Jido.Flow.Registry.entries(flow), acc, fn {_, entry}, acc ->
        versions(entry, acc)
      end)

  defp versions(_, acc), do: acc
end
