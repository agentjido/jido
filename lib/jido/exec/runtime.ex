defmodule Jido.Exec.Runtime do
  @moduledoc false

  alias Jido.Exec.{Frame, Portable, Validation, Wait}
  alias Jido.Instruction
  alias Runic.Workflow
  alias Runic.Workflow.{Fact, Invokable, Runnable}
  alias Runic.Workflow.Events.{ActivationConsumed, FactProduced}

  @reserved [
    :__jido_exec_durable__,
    :__jido_wait_host__,
    :__jido_wait_result__,
    :jido_exec_capabilities
  ]

  @doc false
  @spec user_context(map()) :: map()
  def user_context(context) do
    waits? = Map.has_key?(context, :__jido_wait_host__)
    context = Map.drop(context, @reserved)

    if waits?,
      do: Map.put(context, :jido_exec_capabilities, [:waits]),
      else: context
  end

  @doc false
  @spec context(map(), boolean()) :: map()
  def context(context, durable? \\ false) do
    context
    |> caller_context()
    |> Map.put(:__jido_exec_durable__, durable?)
  end

  @doc false
  @spec caller_context(map()) :: map()
  def caller_context(context), do: Map.drop(context, @reserved)

  @doc false
  @spec run(Jido.Exec.task_supervisor(), pid(), (-> term())) :: term()
  def run(task_supervisor, group_leader, work) do
    caller = self()

    task =
      Task.Supervisor.async_nolink(task_supervisor, fn ->
        Process.group_leader(self(), group_leader)
        watcher = watch_caller(caller, self())
        result = work.()
        stop_watcher(watcher)
        result
      end)

    case Task.yield(task, :infinity) do
      {:ok, result} -> result
      {:exit, reason} -> {:error, execution_task_error(reason)}
    end
  rescue
    exception ->
      {:error, execution_task_error(exception)}
  catch
    kind, reason ->
      {:error, execution_task_error({kind, reason})}
  end

  # The execution task is not linked to the caller, so a killed Action cannot
  # exit the caller. The linked watcher kills the task, and the processes
  # linked to it, when the caller exits.
  defp watch_caller(caller, task) do
    spawn_link(fn ->
      caller_monitor = Process.monitor(caller)
      task_monitor = Process.monitor(task)

      receive do
        {:DOWN, ^caller_monitor, :process, ^caller, _reason} -> Process.exit(task, :kill)
        {:DOWN, ^task_monitor, :process, ^task, _reason} -> :ok
      end
    end)
  end

  defp stop_watcher(watcher) do
    Process.unlink(watcher)
    Process.exit(watcher, :kill)
  end

  defp execution_task_error(reason) do
    Jido.Error.execution_error("Exec task exited", %{
      phase: :execution_task,
      reason: reason
    })
  end

  @doc false
  @spec flow_input(Jido.Instruction.t()) :: {:ok, Jido.Instruction.t()} | {:error, Exception.t()}
  def flow_input(%Instruction{kind: :action} = instruction), do: {:ok, instruction}

  def flow_input(%Instruction{kind: :flow} = instruction) do
    with {:ok, params} <-
           Validation.input(instruction.target, instruction.params, %{phase: :flow_input}) do
      {:ok, %{instruction | params: params}}
    end
  end

  @doc false
  @spec portable(Jido.Instruction.t()) :: :ok | {:error, Exception.t()}
  def portable(%Instruction{} = instruction) do
    with :ok <- Portable.validate(instruction.params, :params),
         :ok <- Portable.validate(instruction.metadata, :metadata) do
      Portable.validate(instruction.context, :context)
    end
  end

  @doc false
  @spec wait_context(map(), term(), Wait.clock()) :: map()
  def wait_context(context, execution_id, clock) when is_map(context) do
    Map.put(context, :__jido_wait_host__, %{execution_id: execution_id, clock: clock})
  end

  @doc false
  @spec pending_waits(Workflow.t()) :: [Wait.t()]
  def pending_waits(workflow) do
    closed = MapSet.new(wait_records(workflow, :jido_wait_resolution), & &1.wait_id)

    workflow
    |> wait_records(:jido_wait_request)
    |> Enum.reject(&MapSet.member?(closed, &1.id))
    |> Enum.sort_by(&{&1.path, &1.id})
    |> Enum.map(&Wait.from_record!/1)
  end

  @doc false
  @spec next_wait_deadline(Workflow.t()) :: non_neg_integer() | nil
  def next_wait_deadline(workflow), do: workflow |> pending_waits() |> Wait.next_deadline()

  @doc false
  @spec resolve_wait(Workflow.t(), Wait.id(), [Wait.candidate()], non_neg_integer()) ::
          {:ok, Workflow.t()} | {:error, Exception.t()}
  def resolve_wait(workflow, wait_id, candidates, now) when is_integer(now) and now >= 0 do
    with :ok <- Wait.validate_candidates(candidates) do
      requests = wait_records(workflow, :jido_wait_request)
      closed = wait_records(workflow, :jido_wait_resolution)

      cond do
        Enum.any?(closed, &(&1.wait_id == wait_id)) ->
          {:ok, workflow}

        request = Enum.find(requests, &(&1.id == wait_id)) ->
          wait = Wait.from_record!(request)

          case Wait.choose(wait, candidates, now) do
            nil -> {:ok, workflow}
            choice -> complete_wait(workflow, request, wait, choice)
          end

        true ->
          wait_error(:stale_target)
      end
    end
  end

  def resolve_wait(_workflow, _wait_id, _candidates, _now), do: wait_error(:invalid_clock)

  defp complete_wait(workflow, record, wait, choice) do
    node = Map.fetch!(workflow.graph.vertices, record.node_hash)
    fact = Map.fetch!(workflow.graph.vertices, record.input_id)

    with {:ok, runnable} <- Invokable.prepare(node, workflow, fact),
         {:ok, frame} <- Frame.merge(Jido.Exec.Fact.value(fact)) do
      output =
        Jido.Exec.Fact.child(fact,
          value: Frame.put_result(frame, node.component, Wait.result(wait, choice), []),
          ancestry: {node.hash, fact.hash}
        )

      resolution =
        Fact.new(
          value: %{
            type: :jido_wait_resolution,
            version: 1,
            wait_id: wait.id,
            path: wait.path,
            selected: choice.option.name,
            accepted_at: choice.at,
            input_id: if(choice.input, do: choice.input.id)
          },
          meta: %{jido_wait_record: true},
          ancestry: {node.hash, fact.hash}
        )

      events = [
        FactProduced.new(output,
          producer_label: :produced,
          weight: runnable.context.ancestry_depth + 1
        ),
        %ActivationConsumed{fact_hash: fact.hash, node_hash: node.hash, from_label: :runnable},
        FactProduced.new(resolution, producer_label: :state_produced)
      ]

      {:ok, Workflow.apply_runnable(workflow, Runnable.complete(runnable, output, events))}
    end
  end

  defp wait_records(workflow, type) do
    for %Fact{meta: %{jido_wait_record: true}, value: %{type: ^type} = value} <-
          Workflow.facts(workflow),
        do: value
  end

  defp wait_error(reason),
    do: {:error, Jido.Error.config_error("wait operation rejected", %{reason: reason})}
end
