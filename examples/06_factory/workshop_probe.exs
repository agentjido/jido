# This probe uses the live provider key and makes model requests.
defmodule Jido.Examples.Factory.WorkshopProbe do
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Factory.Conversation
  alias Jido.Examples.Factory.IEx, as: Chat

  def run do
    env_file = Path.expand("../../.env", __DIR__)
    {:ok, variables} = Dotenvy.source([env_file, System.get_env()])
    System.put_env(variables)
    {:ok, session} = Chat.start(:workshop, context: %{llm_opts: [max_tokens: 500]})
    table = :ets.new(__MODULE__, [:bag, :public])
    handler = {__MODULE__, make_ref()}
    event = [:jido, :agent_server, :signal, :stop]
    :ok = :telemetry.attach(handler, event, &__MODULE__.capture/4, {table, session.factory_id})

    try do
      IO.puts("Live workshop probe: #{Jido.Examples.Factory.Model.model()}")

      ask(
        session,
        "inspect",
        "Use factory_status to inspect the factory. Report its queue, capacity, and schedule."
      )

      ensure(count(table, "factory.command") > 0, "The model did not inspect factory status")

      ask(session, "batch", "add 3 jobs to the factory")
      factory = Jido.whereis_agent(session.jido, session.factory_id)
      ids = Enum.map(1..3, &"batch/#{&1}")
      jobs = Server.agent(factory).state.jobs
      ensure(Enum.sort(Map.keys(jobs)) == ids, "The model did not create three distinct jobs")

      ensure(
        Enum.map(ids, &jobs[&1].goal) == Enum.map(1..3, &"Demonstration job #{&1}"),
        "The model did not use numbered demo goals"
      )

      ensure(count(table, "factory.submit_jobs") == 1, "The model did not submit one batch")

      await(
        fn ->
          Enum.count(Server.agent(factory).state.jobs, fn {_, job} -> job.status == :completed end) ==
            3
        end,
        30_000
      )

      jobs = Server.agent(factory).state.jobs

      ask(
        session,
        "results",
        "Use factory_job to inspect job batch/1 and factory_events with job_id batch/1 to read its progress. Report its final result."
      )

      ensure(count(table, "factory.inspect") >= 2, "The model did not read job and event details")
      {:ok, status} = Chat.status(session)

      ensure(
        status.active_job_id == "" and status.queued_job_ids == [],
        "The factory still has work"
      )

      ensure(
        status.scheduler.enabled and status.max_concurrent_jobs == 1,
        "Factory capacity or schedule is incorrect"
      )

      events = Server.agent(factory).state.events

      for [first, second] <- Enum.chunk_every(ids, 2, 1, :discard) do
        done = Enum.find_index(events, &(&1.job_id == first and &1.status == "completed"))

        started =
          Enum.find_index(
            events,
            &(&1.job_id == second and &1.detail == "Started demonstration job")
          )

        ensure(
          is_integer(done) and is_integer(started) and done < started,
          "Work items overlapped"
        )
      end

      await(fn ->
        Enum.all?(jobs, fn {_, job} -> Jido.whereis_agent(session.jido, job.worker_id) == nil end)
      end)

      IO.puts(
        "PASS: live model tools, one batch of three jobs, one-second scheduling, FIFO order, worker cleanup, and feedback."
      )
    after
      :telemetry.detach(handler)
      :ets.delete(table)
      Chat.stop(session)
    end
  end

  def capture(_event, _measurements, metadata, {table, factory_id}) do
    if metadata[:agent_id] == factory_id do
      :ets.insert(table, {metadata[:signal_type], System.unique_integer([:positive])})
    end
  end

  defp count(table, type), do: length(:ets.lookup(table, type))

  defp ask(session, id, text) do
    IO.puts("probe> #{text}")
    pid = Jido.whereis_agent(session.jido, session.conversation_id)
    {:ok, _} = Conversation.ask(pid, id, text, context: session.context)
    await(fn -> Server.agent(pid).state.status == :idle end, 120_000)
    state = Server.agent(pid).state
    ensure(state.error == "", state.error)
  end

  defp ensure(true, _message), do: :ok
  defp ensure(false, message), do: raise(message)

  defp await(check, timeout \\ 5_000),
    do: wait_until(check, System.monotonic_time(:millisecond) + timeout)

  defp wait_until(check, deadline) do
    if check.() do
      :ok
    else
      ensure(System.monotonic_time(:millisecond) < deadline, "Probe timed out")

      receive do
      after
        25 -> wait_until(check, deadline)
      end
    end
  end
end

Jido.Examples.Factory.WorkshopProbe.run()
