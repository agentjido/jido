Code.require_file("support/report.exs", __DIR__)

case System.argv() do
  [before_path, after_path, output_path] ->
    before = before_path |> File.read!() |> JSON.decode!()
    after_report = after_path |> File.read!() |> JSON.decode!()
    File.write!(output_path, JidoCoreBench.Report.compare!(before, after_report))
    IO.puts("Wrote #{output_path}")

  _ ->
    raise ArgumentError, "usage: mix run bench/compare.exs BEFORE.json AFTER.json COMPARISON.md"
end
