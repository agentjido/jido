Code.require_file("report.exs", __DIR__)

JidoTest.Property.ActionFlow.Report.check!(
  Path.join(Mix.Project.build_path(), "action-flow-property-report.json"),
  JidoTest.Property.ActionFlow.Report.fuzz_ids()
)

IO.puts("Action and Flow property report passed; all required fuzz cases completed.")
