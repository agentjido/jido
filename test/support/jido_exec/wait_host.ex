defmodule Jido.Test.Exec.WaitHost do
  @moduledoc false

  alias Jido.Exec.Runtime
  alias Jido.Exec.Wait, as: WaitValue
  alias Jido.Exec.Node.Wait
  alias Runic.Workflow
  alias Runic.Workflow.{CausalContext, Fact, Runnable}
  alias Runic.Workflow.Events.FactProduced

  @typedoc "A host input with a stable ID, event name, payload, and wait ID or early path."
  @type input :: %{
          required(:id) => String.t(),
          required(:event) => String.t(),
          required(:payload) => map(),
          optional(:wait_id) => String.t(),
          optional(:path) => [String.t()],
          optional(:expires_at) => non_neg_integer()
        }
  @typedoc "A quiescent workflow is waiting, complete, failed, or cancelled."
  @type status ::
          {:waiting, [map()]}
          | {:complete, Jido.Exec.exec_result()}
          | {:failed, Jido.Exec.exec_result()}
          | :cancelled

  @doc "Starts a portable execution with a stable host ID and an explicit `now:` in milliseconds."
  @spec start(term(), term(), map(), map(), keyword()) :: {:ok, Workflow.t()} | {:error, term()}
  def start(execution_id, target, params \\ %{}, context \\ %{}, opts \\ []) do
    protect(fn -> do_start(execution_id, target, params, context, opts) end)
  end

  defp do_start(execution_id, target, params, context, opts) do
    with {:ok, now} <- clock(opts),
         :ok <- options(opts, [:now, :max_buffered_inputs]),
         true <- is_map(context),
         limit = Keyword.get(opts, :max_buffered_inputs, 128),
         true <- is_integer(limit) and limit > 0,
         :ok <- Runtime.validate_local(execution_id, :execution_id),
         {:ok, instruction} <- Jido.Instruction.resolve(target, params, context),
         {:ok, instruction} <- Runtime.flow_instruction(instruction),
         :ok <- Runtime.portable(instruction),
         {:ok, workflow} <- Jido.Exec.compile(%{instruction | context: %{}}, []) do
      context = instruction.context

      state = %{
        type: :jido_wait_host,
        execution_id: execution_id,
        now: now,
        revision: 0,
        limit: limit,
        cancelled?: false
      }

      fact =
        Fact.new(
          value: instruction.params,
          id:
            Runic.Identity.digest(
              :fact_occurrence,
              %{kind: :jido_wait_root, execution_id: execution_id}
            )
        )

      workflow =
        workflow
        |> Workflow.enable_event_emission()
        |> record(state)
        |> runtime(context, state)
        |> Workflow.react_until_satisfied(fact)

      workflow = settle(workflow, context, state)

      if failure?(workflow),
        do: Jido.Exec.Result.project(workflow),
        else: {:ok, workflow}
    else
      false -> error(:invalid_buffer_limit)
      {:error, _} = error -> error
    end
  end

  @doc "Returns the current outcome and pending wait requests. Waiting is not completion."
  @spec status(Workflow.t()) :: status()
  def status(workflow) do
    state = state(workflow)
    pending = pending(workflow)
    result = Jido.Exec.Result.project(workflow)

    cond do
      state.cancelled? -> :cancelled
      failure?(workflow) -> {:failed, result}
      pending != [] -> {:waiting, Enum.map(pending, &public_request/1)}
      match?({:error, _}, result) -> {:failed, result}
      true -> {:complete, result}
    end
  end

  @doc "Accepts one addressed event. Equal retries are inert; conflicting IDs fail."
  @spec accept(Workflow.t(), input(), map(), keyword()) :: {:ok, Workflow.t()} | {:error, term()}
  def accept(workflow, input, context \\ %{}, opts \\ []) do
    protect(fn -> do_accept(workflow, input, context, opts) end)
  end

  defp do_accept(workflow, input, context, opts) do
    with {:ok, state} <- prepare(workflow, context, opts),
         :ok <- validate_input(input),
         :ok <- Runtime.validate_local(input, :wait_event) do
      case Enum.find(records(workflow, :jido_wait_input), &(&1.input.id == input.id)) do
        %{input: ^input} -> {:ok, workflow}
        %{} -> error(:conflicting_input_id)
        nil -> accept_new(workflow, input, context, state)
      end
    end
  end

  @doc "Resolves deadlines and buffered inputs using an explicit host clock."
  @spec advance(Workflow.t(), map(), keyword()) :: {:ok, Workflow.t()} | {:error, term()}
  def advance(workflow, context \\ %{}, opts \\ []) do
    protect(fn -> do_advance(workflow, context, opts) end)
  end

  defp do_advance(workflow, context, opts) do
    with {:ok, state} <- prepare(workflow, context, opts),
         false <- state.cancelled? do
      if state.now == state(workflow).now,
        do: {:ok, workflow},
        else: {:ok, workflow |> record(state) |> settle(context, state)}
    else
      true -> error(:cancelled)
      {:error, _} = error -> error
    end
  end

  @doc "Cancels all pending descendant waits. Completed work and external I/O remain committed."
  @spec cancel(Workflow.t()) :: {:ok, Workflow.t()} | {:error, term()}
  def cancel(workflow) do
    case status(workflow) do
      {:waiting, _} ->
        state = state(workflow)
        {:ok, record(workflow, %{state | cancelled?: true, revision: state.revision + 1})}

      :cancelled ->
        {:ok, workflow}

      _ ->
        error(:already_complete)
    end
  end

  defp accept_new(workflow, input, context, state) do
    cond do
      state.cancelled? ->
        error(:cancelled)

      Map.get(input, :expires_at, state.now + 1) <= state.now ->
        error(:expired_input)

      not match?({:waiting, _}, status(workflow)) ->
        error(:stale_target)

      not addressable?(workflow, input) ->
        error(:stale_target)

      not useful_input?(workflow, input) ->
        error(:unmatched_input)

      Map.has_key?(input, :path) and length(buffered(workflow, state.now)) >= state.limit ->
        error(:buffer_full)

      true ->
        receipt = %{
          type: :jido_wait_input,
          input: input,
          accepted_at: state.now,
          order: state.revision
        }

        {:ok, workflow |> record(state) |> record(receipt) |> settle(context, state)}
    end
  end

  defp prepare(workflow, context, opts) do
    with {:ok, now} <- clock(opts),
         :ok <- options(opts, [:now]),
         :ok <- Runtime.validate_local(context, :context),
         true <- is_map(context) do
      state = state(workflow)

      if now >= state.now,
        do: {:ok, %{state | now: now, revision: state.revision + 1}},
        else: error(:clock_moved_backwards)
    else
      false -> error(:invalid_context)
      {:error, _} = error -> error
    end
  end

  defp settle(workflow, context, state) do
    workflow = runtime(workflow, context, state)

    requests = if failure?(workflow), do: [], else: pending(workflow)

    inputs = buffered(workflow, state.now)

    resolved =
      Enum.reduce(requests, workflow, fn request, current ->
        candidates = Enum.filter(inputs, &addressed?(&1.input, request))
        {:ok, next} = Runtime.resolve_wait(current, request.id, candidates, state.now)
        next
      end)

    if resolved == workflow,
      do: workflow,
      else: resolved |> Workflow.react_until_satisfied() |> settle(context, state)
  end

  defp pending(workflow) do
    if state(workflow).cancelled?, do: [], else: Runtime.pending_waits(workflow)
  end

  defp buffered(workflow, now) do
    consumed = records(workflow, :jido_wait_resolution) |> MapSet.new(& &1.input_id)

    closed = records(workflow, :jido_wait_resolution)

    records(workflow, :jido_wait_input)
    |> Enum.reject(fn receipt ->
      Enum.any?(closed, fn resolution ->
        Map.get(receipt.input, :wait_id) == resolution.wait_id or
          Map.get(receipt.input, :path) == resolution.path
      end) or
        MapSet.member?(consumed, receipt.input.id) or
        Map.get(receipt.input, :expires_at, now + 1) <= now
    end)
    |> Enum.sort_by(& &1.order)
  end

  defp public_request(request) do
    case request.options do
      [option] -> Map.merge(request, Map.take(option, [:event, :match, :deadline]))
      _ -> request
    end
  end

  defp addressable?(workflow, %{wait_id: id}), do: Enum.any?(pending(workflow), &(&1.id == id))

  defp addressable?(workflow, %{path: path}) do
    not Enum.any?(records(workflow, :jido_wait_request), &(&1.path == path)) and
      Enum.any?(Multigraph.vertices(workflow.graph), fn
        %Wait{node_path: ^path} -> true
        _ -> false
      end)
  end

  defp addressed?(%{wait_id: id}, request), do: id == request.id
  defp addressed?(%{path: path}, request), do: path == request.path

  defp state(workflow), do: records(workflow, :jido_wait_host) |> Enum.max_by(& &1.revision)

  defp records(workflow, type) do
    for %Fact{meta: %{jido_wait_record: true}, value: %{type: ^type} = value} <-
          Multigraph.vertices(workflow.graph),
        do: value
  end

  defp root_id(workflow) do
    Enum.find_value(workflow.graph.vertices, fn
      {id, %Runic.Workflow.Root{}} -> id
      _ -> nil
    end)
  end

  defp record(workflow, value) do
    value = Map.put(value, :version, 1)

    fact =
      Fact.new(
        value: value,
        meta: %{jido_wait_record: true},
        ancestry: {root_id(workflow), nil}
      )

    runnable =
      root_id(workflow)
      |> Runnable.new(Workflow.root(), fact, %CausalContext{})
      |> Runnable.complete(nil, [FactProduced.new(fact, producer_label: :state_produced)])

    Workflow.apply_runnable(workflow, runnable)
  end

  defp protect(work), do: Runtime.run(Jido.Exec.TaskSupervisor, Process.group_leader(), work)

  defp runtime(workflow, context, state),
    do:
      Workflow.put_run_context(workflow, %{
        _global:
          context
          |> Runtime.caller_context()
          |> Runtime.wait_context(state.execution_id, state.now)
      })

  defp useful_input?(_workflow, %{path: _path}), do: true

  defp useful_input?(workflow, input) do
    Enum.any?(pending(workflow), fn request ->
      addressed?(input, request) and
        WaitValue.matches?(request, input.event, input.payload)
    end)
  end

  defp failure?(workflow),
    do:
      Enum.any?(
        workflow.runnable_events,
        &is_struct(&1, Runic.Workflow.RunnableFailed)
      )

  defp validate_input(%{id: id, event: event, payload: payload} = input)
       when is_binary(id) and byte_size(id) > 0 and is_binary(event) and byte_size(event) > 0 and
              is_map(payload) and not is_struct(payload) do
    addressed =
      case Map.take(input, [:wait_id, :path]) do
        %{wait_id: id} = address when map_size(address) == 1 ->
          is_binary(id) and byte_size(id) > 0

        %{path: path} = address when map_size(address) == 1 ->
          is_list(path) and path != [] and not List.improper?(path) and
            Enum.all?(path, &is_binary/1)

        _ ->
          false
      end

    expiry = Map.get(input, :expires_at, 0)

    if addressed and is_integer(expiry) and expiry >= 0 and
         Map.keys(input) -- [:id, :event, :payload, :wait_id, :path, :expires_at] == [],
       do: :ok,
       else: error(:invalid_input)
  end

  defp validate_input(_input), do: error(:invalid_input)

  defp clock(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      case Keyword.get(opts, :now) do
        now when is_integer(now) and now >= 0 -> {:ok, now}
        _ -> error(:invalid_clock)
      end
    else
      error(:invalid_options)
    end
  end

  defp clock(_opts), do: error(:invalid_options)

  defp options(opts, allowed) do
    if Keyword.keys(opts) -- allowed == [], do: :ok, else: error(:invalid_options)
  end

  defp error(reason),
    do: {:error, Jido.Error.config_error("wait host rejected operation", %{reason: reason})}
end
