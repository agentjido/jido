# Run from the project root. This measures a local fleet, not an Actor hierarchy.
alias Jido.Actor.Server
alias Jido.Examples.MinimalActor
jido = JidoSurvey.Fleet
count = 1_500
{:ok, supervisor} = Jido.start_link(name: jido)
baseline = :erlang.memory(:total)

try do
  {start_us, actors} =
    :timer.tc(fn ->
      1..count
      |> Task.async_stream(
        fn index ->
          {:ok, actor} = Jido.start_actor(jido, MinimalActor, id: "fleet-#{index}")
          actor
        end,
        max_concurrency: 32,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, actor} -> actor end)
    end)

  ^count = Jido.actor_count(jido)
  peak_ready_memory = :erlang.memory(:total)

  {work_us, latencies} =
    :timer.tc(fn ->
      actors
      |> Task.async_stream(
        fn actor ->
          {us, {:ok, result}} = :timer.tc(fn -> MinimalActor.increment(actor, 1) end)
          %{count: 1} = result.state
          %{state_version: 1} = Server.snapshot(actor)
          us
        end,
        max_concurrency: 32,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, us} -> us end)
    end)

  {stop_us, _} =
    :timer.tc(fn ->
      actors
      |> Task.async_stream(
        fn actor ->
          ref = Process.monitor(actor)
          :ok = Jido.stop_actor(jido, actor)

          receive do
            {:DOWN, ^ref, :process, ^actor, _} -> :ok
          after
            5_000 -> raise "Actor did not stop"
          end
        end,
        max_concurrency: 32,
        timeout: 30_000
      )
      |> Enum.each(fn {:ok, :ok} -> :ok end)
    end)

  0 = Jido.actor_count(jido)
  [] = Task.Supervisor.children(Jido.task_supervisor_name(jido))

  IO.inspect(
    %{
      actors: count,
      successful_commits: count,
      concurrency: 32,
      start_ms: start_us / 1_000,
      work_ms: work_us / 1_000,
      stop_ms: stop_us / 1_000,
      p50_call_us: Enum.at(Enum.sort(latencies), div(count, 2)),
      p95_call_us: Enum.at(Enum.sort(latencies), trunc(count * 0.95)),
      ready_vm_memory_delta_bytes: peak_ready_memory - baseline,
      remaining_actors: 0,
      remaining_owned_tasks: 0
    },
    label: "Local fleet audit"
  )
after
  Supervisor.stop(supervisor)
end
