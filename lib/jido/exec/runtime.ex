defmodule Jido.Exec.Runtime do
  @moduledoc false

  alias Jido.Error
  alias Jido.Exec.{Frame, Validation, Wait}
  alias Jido.Flow.Preparation
  alias Jido.Instruction
  alias Runic.Workflow
  alias Runic.Workflow.{Fact, Invokable, Runnable}
  alias Runic.Workflow.Events.{ActivationConsumed, FactProduced}

  @typep local_type :: :pid | :port | :reference | :function

  @reserved [
    :__jido_exec_durable__,
    :__jido_exec_max_concurrency__,
    :__jido_wait_host__,
    :__jido_wait_result__,
    :jido_exec_capabilities
  ]

  @max_concurrency_key {__MODULE__, :max_concurrency}
  @quiet_failure_log_key {__MODULE__, :quiet_failure_log}

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
  @spec with_execution_context(map(), (-> term())) :: term()
  def with_execution_context(context, work) when is_map(context) and is_function(work, 0) do
    previous = Process.get(@max_concurrency_key)
    Process.put(@max_concurrency_key, Map.get(context, :__jido_exec_max_concurrency__, 1))

    try do
      work.()
    after
      if is_nil(previous),
        do: Process.delete(@max_concurrency_key),
        else: Process.put(@max_concurrency_key, previous)
    end
  end

  # Runic logs each failed runnable at `:warning` with its node and error, and
  # both can hold caller values. The caller already receives the error, so the
  # process that applies runnables keeps that line out of the logs.
  @doc false
  @spec quiet_failure_log() :: :ok
  def quiet_failure_log do
    Process.put(@quiet_failure_log_key, true)
    Logger.put_process_level(self(), :error)
  end

  # Action callbacks and telemetry handlers can run in that same process. They
  # keep the application's log level.
  @doc false
  @spec with_application_logging((-> result)) :: result when result: term()
  def with_application_logging(work) when is_function(work, 0) do
    if Process.delete(@quiet_failure_log_key) do
      Logger.delete_process_level(self())

      try do
        work.()
      after
        quiet_failure_log()
      end
    else
      work.()
    end
  end

  @doc false
  @spec max_concurrency() :: pos_integer()
  def max_concurrency do
    case Process.get(@max_concurrency_key, 1) do
      value when is_integer(value) and value > 0 -> value
      _value -> 1
    end
  end

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
    with :ok <- validate_local(instruction.params, :params),
         :ok <- validate_local(instruction.metadata, :metadata) do
      validate_local(instruction.context, :context)
    end
  end

  @doc false
  @spec handoff(term(), term()) :: {:ok, Instruction.t()} | {:error, Exception.t()}
  def handoff(target, params) do
    with {:ok, instruction} <- Instruction.resolve(target, params),
         :ok <- unbound_handoff(instruction),
         :ok <- validate_handoff_target(instruction),
         {:ok, params} <- Validation.input(instruction.target, instruction.params),
         :ok <- validate_local(params, :handoff_input) do
      {:ok, %{instruction | params: params}}
    end
  end

  @doc false
  @spec validate_local(term(), atom()) :: :ok | {:error, Exception.t()}
  def validate_local(value, field) do
    case walk_local(value, [field]) do
      :ok ->
        :ok

      {:error, type, path} ->
        {:error,
         Error.execution_error("durable execution data contains a process-local value", %{
           phase: :durability,
           reason: :non_portable_durable_value,
           type: type,
           path: path,
           retry: false
         })}
    end
  end

  @spec walk_local(term(), [term()]) :: :ok | {:error, local_type(), [term()]}
  defp walk_local(term, path)
       when is_pid(term) or is_reference(term) or is_port(term) or is_function(term),
       do: {:error, local_type(term), path}

  defp walk_local(term, path) when is_map(term) do
    term
    |> Map.to_list()
    |> Enum.reduce_while(:ok, fn {key, value}, :ok ->
      with :ok <- walk_local(key, path ++ [:key]),
           :ok <- walk_local(value, path ++ [key]) do
        {:cont, :ok}
      else
        {:error, _type, _path} = error -> {:halt, error}
      end
    end)
  end

  defp walk_local(term, path) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {value, index}, :ok ->
      case walk_local(value, path ++ [index]) do
        :ok -> {:cont, :ok}
        {:error, _type, _path} = error -> {:halt, error}
      end
    end)
  end

  defp walk_local([], _path), do: :ok
  defp walk_local([_head | _tail] = term, path), do: walk_local_list(term, path, 0)
  defp walk_local(_term, _path), do: :ok

  defp walk_local_list([], _path, _index), do: :ok

  defp walk_local_list([value | rest], path, index) do
    case walk_local(value, path ++ [index]) do
      :ok when is_list(rest) -> walk_local_list(rest, path, index + 1)
      :ok -> walk_local(rest, path ++ [:tail])
      {:error, _type, _path} = error -> error
    end
  end

  defp local_type(term) when is_pid(term), do: :pid
  defp local_type(term) when is_port(term), do: :port
  defp local_type(term) when is_reference(term), do: :reference
  defp local_type(term) when is_function(term), do: :function

  defp unbound_handoff(%Instruction{context: context, metadata: metadata})
       when map_size(context) == 0 and map_size(metadata) == 0,
       do: :ok

  defp unbound_handoff(_instruction) do
    {:error,
     Error.config_error("handoff target must not bind runtime context or metadata", %{
       reason: :bound_handoff_runtime
     })}
  end

  defp validate_handoff_target(%Instruction{kind: :action} = instruction),
    do: Instruction.validate_resolved(instruction)

  defp validate_handoff_target(%Instruction{kind: :flow} = instruction) do
    with :ok <- Instruction.validate_resolved(instruction),
         {:ok, flow} <- Preparation.from_instruction(instruction),
         {:ok, _attrs, _analysis, _children} <- Preparation.prepare(flow, [], %{}),
         do: :ok
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
