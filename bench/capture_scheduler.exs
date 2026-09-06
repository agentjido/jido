Code.require_file("support/suite.exs", __DIR__)

defmodule JidoCoreBench.SchedulerCapture do
  @moduledoc false
  alias JidoCoreBench.{Fixtures, Measure, SchedulerCases}

  def run do
    :erlang.trace_pattern({Task, :async, 1}, true, [])

    try do
      for kind <- [:small, :large_map, :large_list, :large_binary], do: capture(kind)
    after
      :erlang.trace_pattern({Task, :async, 1}, false, [])
    end
  end

  defp capture(kind) do
    owner = self()

    {caller, monitor} =
      spawn_monitor(fn ->
        receive do
          :run ->
            runtime = SchedulerCases.setup(kind, %{})

            try do
              Fixtures.equal!(SchedulerCases.deliver(runtime), {:previous, :idle})
            after
              SchedulerCases.cleanup(runtime)
            end

            send(owner, {:complete, self()})
        end
      end)

    :erlang.trace(caller, true, [:call, {:tracer, self()}])
    send(caller, :run)

    receive do
      {:DOWN, ^monitor, :process, ^caller, :normal} -> :ok
      {:DOWN, ^monitor, :process, ^caller, reason} -> raise "capture failed: #{inspect(reason)}"
    after
      10_000 ->
        Process.exit(caller, :kill)
        raise "scheduler capture timed out"
    end

    receive do
      {:complete, ^caller} -> :ok
    after
      0 -> raise "scheduler task did not complete"
    end

    ref = :erlang.trace_delivered(caller)

    receive do
      {:trace_delivered, ^caller, ^ref} -> :ok
    after
      5_000 -> raise "scheduler call trace did not complete"
    end

    fun =
      receive do
        {:trace, ^caller, :call, {Task, :async, [fun]}} when is_function(fun, 0) -> fun
      after
        0 -> raise "scheduler task function was not captured"
      end

    receive do
      {:trace, ^caller, :call, {Task, :async, _args}} -> raise "more than one task was captured"
    after
      0 -> :ok
    end

    {:env, env} = Function.info(fun, :env)

    %{
      payload: kind,
      captures_runtime: Enum.any?(env, &(is_map(&1) and Map.has_key?(&1, :desired_cron))),
      function_term: Measure.term_size(fun)
    }
  end
end

{opts, args, invalid} = OptionParser.parse(System.argv(), strict: [output: :string])

if args != [] or invalid != [],
  do: raise(ArgumentError, "usage: mix run bench/capture_scheduler.exs --output PATH")

report =
  Map.merge(JidoCoreBench.Suite.metadata(), %{
    schema_version: 1,
    method:
      "trace the actual scheduler Task.async argument; check idle result and teardown; copy the function",
    limitations: [
      "This traced diagnostic supplies no timing evidence.",
      "It runs Runtime.handle_info with an owned plugin-state reply fixture, not a complete Server Turn.",
      "Copied function heap is one argument transfer, not total task traffic or binary allocation."
    ],
    cases: JidoCoreBench.SchedulerCapture.run()
  })

output = Keyword.get(opts, :output, "bench/results/scheduler-capture.json")
File.mkdir_p!(Path.dirname(output))
File.write!(output, JSON.encode!(report))
IO.puts("Wrote #{output}")
