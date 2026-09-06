Code.require_file("../../../bench/support/suite.exs", __DIR__)

alias JidoCoreBench.Suite

ids = [
  "observe/batch/noop/correlation_false/metadata_0/100",
  "observe/batch/legacy/correlation_true/metadata_0/100",
  "observe/batch/legacy/correlation_true/metadata_1000/100",
  "server/admit/large_binary",
  "server/call/small",
  "server/failure/large_binary",
  "server/failure/small",
  "server/snapshot/large_binary",
  "server/snapshot/small",
  "server/start_stop/large_binary",
  "server/flow/small"
]

defmodule JidoCoreSpanHeap do
  def invoke(workload) do
    prepared = workload.setup.(%{})

    try do
      result = workload.run.(prepared)
      :ok = workload.check.(result)
      :ok = Map.get(workload, :verify, fn _, _ -> :ok end).(prepared, result)
    after
      Map.get(workload, :cleanup, fn _ -> :ok end).(prepared)
    end

    JidoCoreBench.Suite.ensure_idle!()
  end
end

{:ok, supervisor} = Jido.start_link(name: JidoCoreBench)

cases =
  try do
    for workload <- Suite.workloads("short"), workload.id in ids do
      :ok = JidoCoreSpanHeap.invoke(workload)

      {:ok, {:call_memory, profile}} =
        :tprof.profile(
          fn -> Enum.each(1..10, fn _ -> JidoCoreSpanHeap.invoke(workload) end) end,
          %{
            type: :call_memory,
            report: :return,
            set_on_spawn: true,
            rootset: [Process.whereis(JidoCoreBench.TaskSupervisor)]
          }
        )

      words =
        Enum.sum(
          for {_module, _function, _arity, counters} <- profile,
              {_pid, _calls, words} <- counters,
              do: words
        )

      %{
        id: workload.id,
        invocations: 10,
        heap_words: words,
        heap_bytes: words * :erlang.system_info(:wordsize)
      }
    end
  after
    Supervisor.stop(supervisor)
  end

{opts, [], []} = OptionParser.parse(System.argv(), strict: [output: :string])
output = Keyword.fetch!(opts, :output)

report =
  Map.merge(Suite.metadata(), %{
    method:
      "OTP tprof call_memory; 10 checked invocations with setup and teardown; caller descendants and benchmark TaskSupervisor",
    limitations: [
      "This measures profiled heap allocation, not peak live memory or off-heap binary allocation.",
      "It includes setup and checks. External application-controller and Logger processes are not included.",
      "Setup runs in the profiled caller so trace context is present for span operations.",
      "Profiling changes execution time. This supplies no timing evidence."
    ],
    probe_sha256: Base.encode16(:crypto.hash(:sha256, File.read!(__ENV__.file)), case: :lower),
    cases: cases
  })

File.mkdir_p!(Path.dirname(output))
File.write!(output, JSON.encode!(report))
IO.puts("Wrote #{output}")
