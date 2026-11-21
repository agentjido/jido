# Load Testing

Follow this guide to load test your own Jido system. It builds a small harness that drives concurrent Turns, records latency and rejections, and proves that processes clean up. Use the results to choose limits and to compare two versions of your code.

Timing results apply only to the machine, code, and data that produced them. Compare runs with the same setup. Do not copy a number from one environment to another.

## Decide what to measure

Write down one question for each run:

| Question | Load shape | Watch |
| --- | --- | --- |
| What latency do callers see at expected traffic? | Steady rate over many Agents | Caller latency, Turn duration |
| What happens when one Agent falls behind? | Many callers, one Agent | `:overloaded` count, `admission.postponed`, mailbox length |
| How many live Agents fit on a node? | Add Agents with realistic state | Memory, process count, scheduler use |
| Does the system leak over time? | Moderate load for hours | Memory and process count return to baseline |
| Can my store keep up? | Durable Agents at a target rate | `jido.persistence.operation.stop.duration`, `conflict` and `indeterminate` counts |

Use your real Actions, state sizes, and store. Replace a paid or rate-limited external service with a local stub that has realistic delays, and say so in your results. An in-memory adapter tells you nothing about your database.

Run the load generator apart from the node under test when you can. Otherwise they compete for schedulers.

## Build the harness

The harness has an Agent under test and a telemetry recorder. The recorder only writes to a public ETS table, so it adds little work to each Turn. The Agent's Action sleeps to stand in for your real work.

```elixir
defmodule LoadGuide.Reserve do
  use Jido.Action,
    name: "load_guide_reserve",
    schema: Jido.Joi.object(%{units: Jido.Joi.integer()})

  @impl Jido.Action
  def run(%{units: units}, %{agent_state: state}) do
    Process.sleep(1)
    {:ok, %{state | reserved: state.reserved + units}}
  end
end

defmodule LoadGuide.Inventory do
  use Jido.Agent, name: "load_guide_inventory"

  state do
    schema Jido.Joi.object(%{reserved: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/inventory"
    route "inventory.reserve", LoadGuide.Reserve, as: :reserve
  end
end

defmodule LoadGuide.Recorder do
  @table :load_guide_turns

  def start do
    :ets.new(@table, [:named_table, :public, :duplicate_bag, write_concurrency: true])

    :telemetry.attach(
      "load-guide-recorder",
      [:jido, :agent_server, :turn, :stop],
      &__MODULE__.handle/4,
      nil
    )
  end

  def handle(_event, %{duration: duration}, %{status: status}, _config) do
    :ets.insert(@table, {status, duration})
  end

  def stop, do: :telemetry.detach("load-guide-recorder")

  def turns(status) do
    @table
    |> :ets.lookup(status)
    |> Enum.map(fn {_status, duration} ->
      System.convert_time_unit(duration, :native, :microsecond)
    end)
  end
end

defmodule LoadGuide.Report do
  def percentile([], _percent), do: nil

  def percentile(values, percent) do
    sorted = Enum.sort(values)
    Enum.at(sorted, min(length(sorted) - 1, trunc(length(sorted) * percent / 100)))
  end

  def summary(values) do
    %{
      count: length(values),
      p50: percentile(values, 50),
      p95: percentile(values, 95),
      p99: percentile(values, 99),
      max: Enum.max(values, fn -> nil end)
    }
  end
end
```

The `run` function below sends Turns from concurrent callers and records what each caller sees. Caller latency includes the queue wait. Turn duration does not. A large gap between them means that requests are waiting.

```elixir
defmodule LoadGuide.Driver do
  alias Jido.AgentServer, as: Server

  def run(servers, opts) do
    callers = Keyword.fetch!(opts, :callers)
    turns = Keyword.fetch!(opts, :turns_per_caller)
    signal = LoadGuide.Inventory.reserve_signal!(%{units: 1})

    1..callers
    |> Task.async_stream(
      fn caller ->
        for turn <- 1..turns do
          server = Enum.at(servers, rem(caller + turn, length(servers)))
          started = System.monotonic_time(:microsecond)
          result = Server.call(server, signal, admission_timeout: 1_000)
          {classify(result), System.monotonic_time(:microsecond) - started}
        end
      end,
      max_concurrency: callers,
      timeout: :infinity
    )
    |> Enum.flat_map(fn {:ok, results} -> results end)
  end

  defp classify({:ok, _agent, _directives}), do: :ok
  defp classify({:error, {:overloaded, _details}}), do: :overloaded
  defp classify({:error, :admission_timeout}), do: :admission_timeout
  defp classify({:error, _reason}), do: :error
end
```

## Run steady load

Start a dedicated instance and spread the load across Agents. The counts here are small so that this guide stays quick. Raise them to your real traffic, and run long enough to pass your warm-up.

```elixir
LoadGuide.Recorder.start()

{:ok, _pid} = Jido.start_link(name: LoadGuide.Jido)

baseline = :erlang.system_info(:process_count)

servers =
  for index <- 1..10 do
    {:ok, server} = Jido.start_agent(LoadGuide.Jido, LoadGuide.Inventory, id: "warehouse-#{index}")
    server
  end

steady = LoadGuide.Driver.run(servers, callers: 10, turns_per_caller: 20)

steady_counts = Enum.frequencies_by(steady, fn {result, _micros} -> result end)
caller_latency = steady |> Enum.map(fn {_result, micros} -> micros end) |> LoadGuide.Report.summary()
turn_duration = LoadGuide.Report.summary(LoadGuide.Recorder.turns(:ok))

%{ok: 200} = steady_counts
200 = caller_latency.count
200 = turn_duration.count
```

All 200 calls commit here, because the load is below the limits. Record `caller_latency` and `turn_duration` along with your code revision, Elixir and OTP versions, core count, and store. They mean nothing without that context.

## Find the overload behavior

Point many callers at one Agent with a small queue. Your callers should see rejections they can handle, and the mailbox should stay flat.

```elixir
{:ok, narrow} =
  Jido.start_agent(LoadGuide.Jido, LoadGuide.Inventory, id: "narrow", max_postponed_signals: 2)

overload = LoadGuide.Driver.run([narrow], callers: 20, turns_per_caller: 5)
overload_counts = Enum.frequencies_by(overload, fn {result, _micros} -> result end)

true = Map.get(overload_counts, :overloaded, 0) > 0
100 = overload_counts |> Map.values() |> Enum.sum()

%{mode: :open, limit: 2} = Jido.AgentServer.status(narrow).admission
```

A rejection returns at once with no work done. Decide how your edge responds. Options include a retry with backoff, a shed response to your client, or more Agents. Never treat a rejection as a committed Turn.

While the load runs, poll `Jido.AgentServer.status/2` for the Agents you care about and sample `admission.message_queue_len`. A mailbox that keeps growing means that requests are arriving faster than the server can admit or reject them.

## Prove cleanup

A load test should end with every process gone. Monitor each worker and activation, stop the Agents, and wait for each `:DOWN`. Do not use a fixed sleep. Then check the process count.

```elixir
all_servers = [narrow | servers]

monitors =
  all_servers
  |> Enum.flat_map(fn server -> [server, Jido.AgentServer.activation(server)] end)
  |> Enum.map(fn pid -> {pid, Process.monitor(pid)} end)

all_servers
|> Task.async_stream(&Jido.stop_agent(LoadGuide.Jido, &1), max_concurrency: 8, timeout: 30_000)
|> Enum.each(fn {:ok, :ok} -> :ok end)

Enum.each(monitors, fn {pid, monitor} ->
  receive do
    {:DOWN, ^monitor, :process, ^pid, _reason} -> :ok
  after
    10_000 -> raise "process #{inspect(pid)} did not stop"
  end
end)

0 = Jido.agent_count(LoadGuide.Jido)
true = :erlang.system_info(:process_count) <= baseline + 5

LoadGuide.Recorder.stop()
```

The small margin allows for unrelated VM processes. In a soak test, repeat the whole cycle and compare `:erlang.memory/0` and the process count at the same point of each cycle. A value that keeps rising across cycles points to a leak. A single rise usually does not.

## Measure on the real path

- **Use a production release.** A development build or a test environment can change results.
- **Turn on your production telemetry and logging.** They are part of the cost you will pay.
- **Test durable Turns against your real store.** Include store latency, and include a restart with `Jido.activate_agent/4` at your Agent count. See [Shutdown and Recovery](shutdown-and-recovery.md).
- **Add failure to the load.** Kill workers during a run, slow your store, and watch what callers see.
- **Change one thing per run.** Keep the seed and data set fixed where you can, and repeat each run to see its variation.

Set your alerts and limits from these results. Keep the raw results, so a later run can compare against them.

## Next steps

- [Deployment and Sizing](deployment-and-performance.md)
- [Metrics and OTel](metrics-and-open-telemetry.md)
- [Admission and Deadlines](../agent-servers/agent-server-admission.md)
