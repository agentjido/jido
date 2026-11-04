Code.require_file("support/suite.exs", __DIR__)

{opts, args, invalid} =
  OptionParser.parse(System.argv(), strict: [profile: :string, output: :string])

if args != [] or invalid != [],
  do:
    raise(
      ArgumentError,
      "usage: mix run bench/signal/run.exs --profile short|scale|smoke|candidates --output tmp/bench/signal/DIRECTORY"
    )

profile = Keyword.get(opts, :profile, "short")
root = Path.expand("tmp/bench/signal")
output = opts |> Keyword.get(:output, Path.join(root, profile)) |> Path.expand()

unless output == root or String.starts_with?(output, root <> "/") do
  raise ArgumentError, "benchmark output must be under tmp/bench/signal"
end

report = Jido.Bench.Signal.Suite.run(profile)
Jido.Bench.Signal.Suite.write!(report, output)
IO.puts("Wrote #{output}/report.json and report.md")
