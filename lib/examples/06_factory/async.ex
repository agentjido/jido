defmodule Jido.Examples.Factory.Async.Request do
  @moduledoc "Portable work intent. Request options and credentials stay in turn context."
  @schema Zoi.struct(__MODULE__, %{
            request_id: Zoi.string(),
            context_key: Zoi.string() |> Zoi.default(""),
            kind: Zoi.enum([:model, :department]),
            input: Zoi.map()
          })
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
  def schema, do: @schema
end

defmodule Jido.Examples.Factory.Async.Cancel do
  @moduledoc false
  @schema Zoi.struct(__MODULE__, %{request_id: Zoi.string()})
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
  def schema, do: @schema
end

defmodule Jido.Examples.Factory.Async.Forget do
  @moduledoc false
  @schema Zoi.struct(__MODULE__, %{context_key: Zoi.string()})
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
  def schema, do: @schema
end

defmodule Jido.Examples.Factory.Async do
  @moduledoc "Starts linked tasks after commit and returns results through Signals. No replay is implied."
  use Jido.Plugin
  alias __MODULE__.{Cancel, Forget, Request, Runtime}

  def directives(_), do: [Request, Cancel, Forget]
  def validate_directive(%{__struct__: module} = value, _), do: Zoi.parse(module.schema(), value)
  def child_spec(init), do: Supervisor.child_spec({Runtime, init}, id: __MODULE__)
  def await_ready(runtime, _), do: GenServer.call(runtime, :ready)

  def dispatch(runtime, directive, context, _),
    do: GenServer.call(runtime, {:dispatch, directive, context.turn_context})

  @doc false
  def result_schema do
    Zoi.object(%{
      request_id: Zoi.string(),
      status: Zoi.enum([:completed, :failed]),
      result: Zoi.map(),
      error: Zoi.string()
    })
  end
end

defmodule Jido.Examples.Factory.Async.Runtime do
  @moduledoc false
  use GenServer
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Factory.{Async, Model, Tools}

  def start_link(init), do: GenServer.start_link(__MODULE__, init)

  @impl true
  def init(init) do
    Process.flag(:trap_exit, true)
    {:ok, %{init: init, jobs: %{}, timers: %{}, contexts: %{}}}
  end

  @impl true
  def handle_call(:ready, _, state), do: {:reply, :ok, state}

  def handle_call({:dispatch, %Async.Request{} = request, context}, _, state) do
    if Map.has_key?(state.jobs, request.request_id) do
      {:reply, {:error, :duplicate_task}, state}
    else
      context = Map.merge(Map.get(state.contexts, request.context_key, %{}), context)

      contexts =
        if request.context_key == "",
          do: state.contexts,
          else: Map.put(state.contexts, request.context_key, context)

      task = Task.async(fn -> execute(request, state.init, context) end)
      timer = Process.send_after(self(), {:deadline, task.ref}, 120_000)

      {:reply, :ok,
       %{
         state
         | jobs: Map.put(state.jobs, request.request_id, task),
           timers: Map.put(state.timers, request.request_id, timer),
           contexts: contexts
       }}
    end
  end

  def handle_call({:dispatch, %Async.Forget{context_key: key}, _}, _, state),
    do: {:reply, :ok, %{state | contexts: Map.delete(state.contexts, key)}}

  def handle_call({:dispatch, %Async.Cancel{request_id: id}, _}, _, state) do
    {task, jobs} = Map.pop(state.jobs, id)
    if task, do: Task.shutdown(task, :brutal_kill)
    {:reply, :ok, clear_timer(%{state | jobs: jobs}, id)}
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    finish(ref, result, state)
  end

  def handle_info({:DOWN, ref, :process, _, _}, state),
    do: finish(ref, {:error, :task_failed}, state)

  def handle_info({:EXIT, _, _}, state), do: {:noreply, state}

  def handle_info({:deadline, ref}, state) do
    case Enum.find(state.jobs, fn {_, task} -> task.ref == ref end) do
      nil ->
        {:noreply, state}

      {_, task} ->
        Task.shutdown(task, :brutal_kill)
        finish(ref, {:error, :job_deadline}, state)
    end
  end

  defp execute(%Async.Request{kind: :model, input: input, request_id: id}, init, context) do
    tools = Tools.definitions(init.jido, input.factory_id, id, context)
    Model.reply(input.messages, Map.put(context, :stream_id, id), tools)
  end

  defp execute(%Async.Request{kind: :department, input: input}, init, context) do
    case Jido.whereis_agent(init.jido, input.agent_id, partition: init.partition) do
      nil ->
        {:error, :department_unavailable}

      pid ->
        signal = Jido.Signal.new!("factory.department.work", input.work, source: "/factory")

        # Department artifacts are returned to the factory, not streamed into chat.
        context = Map.drop(context, [:on_stream, :stream_id])

        case Server.call(pid, signal, context: context, timeout: 60_000) do
          {:ok, agent} -> {:ok, agent.state.result}
          {:error, reason} -> {:error, reason}
        end
    end
  catch
    :exit, _ -> {:error, :department_unavailable}
  end

  defp finish(ref, result, state) do
    case Enum.find(state.jobs, fn {_, task} -> task.ref == ref end) do
      nil ->
        {:noreply, state}

      {id, _} ->
        data =
          case result do
            {:ok, value} ->
              %{request_id: id, status: :completed, result: value, error: ""}

            {:error, reason} ->
              %{
                request_id: id,
                status: :failed,
                result: %{},
                error: Jido.Examples.Factory.Error.message(reason)
              }
          end

        signal = Jido.Signal.new!("factory.async.result", data, source: "/factory/async")
        Server.cast(state.init.agent_server, signal)
        {:noreply, clear_timer(%{state | jobs: Map.delete(state.jobs, id)}, id)}
    end
  end

  @impl true
  def terminate(_, state) do
    Enum.each(state.jobs, fn {_, task} -> Task.shutdown(task, :brutal_kill) end)
    :ok
  end

  defp clear_timer(state, id) do
    {timer, timers} = Map.pop(state.timers, id)
    if timer, do: Process.cancel_timer(timer)
    %{state | timers: timers}
  end
end
