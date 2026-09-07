defmodule JidoCoreBench.SchedulerServer do
  @moduledoc false
  use GenServer
  alias JidoCoreBench.Fixtures, as: F

  @impl true
  def init(context), do: {:ok, context}

  # This fixture supplies the public plugin-state reply. It does not run a Turn.
  @impl true
  def handle_call({:plugin_state, Jido.Plugin.Scheduler}, _from, context) do
    F.barrier(context)
    {:reply, {:ok, %{cron: %{}}}, context}
  end
end

defmodule JidoCoreBench.SchedulerCases do
  @moduledoc false
  alias Jido.Plugin.{Init, Scheduler}
  alias Jido.Plugin.Scheduler.Runtime
  alias JidoCoreBench.Fixtures, as: F

  def workloads(payloads) do
    for kind <- payloads do
      F.checked(
        "scheduler/task_capture/#{kind}",
        &setup(kind, &1),
        &deliver/1,
        &F.equal!(&1, {:previous, :idle})
      )
      |> Map.put(:cleanup, &cleanup/1)
    end
  end

  def setup(kind, context) do
    {:ok, server} = GenServer.start_link(JidoCoreBench.SchedulerServer, context)
    previous_trap = Process.flag(:trap_exit, true)

    try do
      {:ok, runtime, {:continue, :reconcile_agent}} =
        Runtime.init(%Init{
          agent_server: server,
          agent_id: "scheduler-bench",
          module: Scheduler,
          options: [delivery_timeout: 5_000]
        })

      signal = Jido.Signal.new!("bench.tick", %{payload: F.payload(kind)}, source: "/bench")

      spec =
        Scheduler.build_cron_spec("0 0 1 1 *", signal)
        |> Map.merge(%{delivery: :durable, generation: 1})

      %{runtime | desired_cron: %{job: spec}, last_delivered_job: :previous}
    after
      Process.flag(:trap_exit, previous_trap)
    end
  end

  def deliver(runtime) do
    {:noreply, pending} = Runtime.handle_info(:deliver_pending, runtime)
    task = pending.delivery_task

    try do
      result = Task.await(task, 5_000)
      F.equal!(pending.desired_cron, runtime.desired_cron)
      result
    after
      Process.cancel_timer(pending.delivery_timeout)
      Task.shutdown(task, :brutal_kill)
    end
  end

  def cleanup(runtime) do
    GenServer.stop(runtime.agent_server)
  end
end
