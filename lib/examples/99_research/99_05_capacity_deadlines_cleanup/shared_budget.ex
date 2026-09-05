defmodule Jido.Examples.SharedBudget.Worker do
  @moduledoc "One review job held at a controlled external-work barrier."
  use Jido.Agent, name: "research_budget_worker"

  agent do
    schema Zoi.object(%{
             job: Zoi.string() |> Zoi.default(""),
             value: Zoi.integer() |> Zoi.default(0)
           })
  end

  routes do
    signal_source "/examples/shared-budget"

    route "budget.work" do
      action %{job: job, value: value},
        name: "research_budget_work",
        schema: Zoi.object(%{job: Zoi.string(), value: Zoi.integer()}),
        context: context do
        send(context.observer, {:budget_work, job, self()})

        receive do
          :finish -> {:ok, %{job: job, value: value * 2}}
          :fail -> {:error, Jido.Action.Error.execution_error("controlled review failure")}
        end
      end

      define :work, args: [:job, :value]
    end
  end
end

defmodule Jido.Examples.SharedBudget do
  @moduledoc """
  An OTP admission service shared by review teams. It uses only public Jido APIs.
  Limits apply to accepted queued jobs and live job Agents. The service owns
  its call Tasks and closes all job Agents on normal shutdown. Queue deadlines
  use an injected monotonic clock. An explicit tick also expires waiting jobs.
  This is a local runtime extension, not a durable or distributed budget.
  """
  use GenServer
  alias __MODULE__.Worker
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def submit(service, team, id, value, deadline),
    do:
      GenServer.call(service, {:submit, %{team: team, id: id, value: value, deadline: deadline}})

  def tick(service), do: GenServer.call(service, :tick)
  def status(service), do: GenServer.call(service, :status)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    {:ok, tasks} = Task.Supervisor.start_link()

    {:ok,
     %{
       jido: Keyword.fetch!(opts, :jido),
       observer: Keyword.fetch!(opts, :observer),
       limit: Keyword.get(opts, :limit, 8),
       queue_limit: Keyword.get(opts, :queue_limit, 32),
       clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
       tasks: tasks,
       active: %{},
       queue: [],
       results: %{},
       seen: MapSet.new(),
       peak: 0
     }}
  end

  @impl true
  def handle_call({:submit, job}, _, state) do
    state = drain(state)

    cond do
      MapSet.member?(state.seen, job.id) ->
        {:reply, {:error, :duplicate}, state}

      job.deadline <= state.clock.() ->
        {:reply, {:error, :expired}, state}

      map_size(state.active) >= state.limit and length(state.queue) >= state.queue_limit ->
        {:reply, {:error, :overloaded}, state}

      true ->
        state =
          %{state | queue: state.queue ++ [job], seen: MapSet.put(state.seen, job.id)} |> drain()

        {:reply, :ok, state}
    end
  end

  def handle_call(:tick, _, state), do: {:reply, :ok, drain(state)}

  def handle_call(:status, _, state) do
    active =
      Map.new(state.active, fn {_, %{job: job, server: server, task: task}} ->
        {job.id, %{team: job.team, server: server, task: task.pid}}
      end)

    {:reply,
     %{
       active: active,
       queued: Enum.map(state.queue, & &1.id),
       results: state.results,
       peak: state.peak,
       task_supervisor: state.tasks
     }, state}
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, settle(state, ref, result)}
  end

  def handle_info({:DOWN, ref, :process, _, reason}, state),
    do: {:noreply, settle(state, ref, {:error, reason})}

  @impl true
  def terminate(_, state) do
    Enum.each(state.active, fn {_, entry} -> stop_agent(entry.server) end)
    Supervisor.stop(state.tasks)
  end

  defp settle(state, ref, result) do
    case Map.pop(state.active, ref) do
      {nil, _} ->
        state

      {entry, active} ->
        stop_agent(entry.server)

        %{state | active: active, results: Map.put(state.results, entry.job.id, result)}
        |> drain()
    end
  end

  defp drain(state) do
    {expired, queue} = Enum.split_with(state.queue, &(&1.deadline <= state.clock.()))
    results = Enum.reduce(expired, state.results, &Map.put(&2, &1.id, {:error, :expired}))
    start_available(%{state | queue: queue, results: results})
  end

  defp start_available(%{queue: [job | rest]} = state)
       when map_size(state.active) < state.limit do
    case Jido.start_agent(state.jido, Worker, restart: :temporary, exec_opts: [timeout: 5_000]) do
      {:ok, server} ->
        observer = state.observer

        task =
          Task.Supervisor.async_nolink(state.tasks, fn ->
            try do
              case Worker.work(server, job.id, job.value, context: %{observer: observer}) do
                {:ok, agent} -> {:ok, agent.state.value}
                error -> error
              end
            catch
              :exit, _ -> {:error, :worker_lost}
            end
          end)

        active = Map.put(state.active, task.ref, %{job: job, server: server, task: task})

        start_available(%{
          state
          | queue: rest,
            active: active,
            peak: max(state.peak, map_size(active))
        })

      {:error, error} ->
        start_available(%{
          state
          | queue: rest,
            results: Map.put(state.results, job.id, {:error, error})
        })
    end
  end

  defp start_available(state), do: state

  defp stop_agent(pid) do
    if Process.alive?(pid), do: Jido.AgentServer.stop(pid)
    :ok
  catch
    :exit, _ -> :ok
  end
end
