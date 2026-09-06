Code.require_file("../../../bench/support/suite.exs", __DIR__)

alias JidoCoreBench.{Fixtures, Suite}

ids = [
  "codec/encode/1",
  "codec/decode/1",
  "codec/check_map/1000/nested",
  "codec/check_map/1000/scalar",
  "codec/check_map/1000/bad_value"
]

cases =
  for workload <- Suite.workloads("short"), workload.id in ids do
    prepared = workload.setup.(%{})

    try do
      :ok = workload.check.(workload.run.(prepared))

      {result, {:call_memory, profile}} =
        :tprof.profile(
          fn -> Enum.reduce(1..100, nil, fn _, _ -> workload.run.(prepared) end) end,
          %{type: :call_memory, report: :return, set_on_spawn: false}
        )

      :ok = workload.check.(result)
      :ok = Map.get(workload, :verify, fn _, _ -> :ok end).(prepared, result)

      functions =
        for {module, function, arity, counters} <- profile do
          %{
            function: "#{inspect(module)}.#{function}/#{arity}",
            calls: Enum.sum(for {_pid, count, _words} <- counters, do: count),
            heap_words: Enum.sum(for {_pid, _count, words} <- counters, do: words)
          }
        end

      words = Enum.sum(Enum.map(functions, & &1.heap_words))
      Fixtures.equal!(length(profile) > 0, true)

      %{
        id: workload.id,
        operations: 100,
        heap_words: words,
        heap_bytes: words * :erlang.system_info(:wordsize),
        functions: Enum.sort_by(functions, & &1.heap_words, :desc)
      }
    after
      Map.get(workload, :cleanup, fn _ -> :ok end).(prepared)
    end
  end

{opts, [], []} = OptionParser.parse(System.argv(), strict: [output: :string])
output = Keyword.fetch!(opts, :output)

report =
  Map.merge(Suite.metadata(), %{
    method:
      "OTP tprof call_memory; 100 calls after setup and warmup; one profiled caller; checked last result",
    limitations: [
      "This measures profiled caller heap allocation, not peak live memory or off-heap binary allocation.",
      "It excludes input setup, initial process argument transfer, and helper processes.",
      "Profiling changes execution time. This supplies no timing evidence."
    ],
    probe_sha256: Base.encode16(:crypto.hash(:sha256, File.read!(__ENV__.file)), case: :lower),
    cases: cases
  })

File.mkdir_p!(Path.dirname(output))
File.write!(output, JSON.encode!(report))
IO.puts("Wrote #{output}")
