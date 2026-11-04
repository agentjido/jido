Mimic.copy(ReqLLM)
Mimic.copy(Jido.Test.AI.Tools.Add)

ExUnit.start(capture_log: true)

{_result, _expected_warnings} =
  Code.with_diagnostics(fn ->
    Code.require_file("support/jido_action/fixtures/missing_callbacks.exs", __DIR__)
  end)

special_quality_tags = [
  :authoring,
  :system,
  :load,
  :throughput,
  :property,
  :fuzz,
  :peer,
  :bench,
  :example,
  :live,
  :service
]

ExUnit.configure(seed: 0, exclude: [:integration, :skip, :flaky] ++ special_quality_tags)

quality_selection = ExUnit.configuration()[:include]

if Enum.any?(quality_selection, fn
     tag when tag in [:property, :fuzz] -> true
     {tag, value} when tag in [:property, :fuzz] -> value != false
     _other -> false
   end) do
  Code.require_file("property/support/report.exs", __DIR__)
  JidoTest.Property.Report.prepare!()

  ExUnit.configure(
    formatters: [
      ExUnit.CLIFormatter,
      JidoTest.Property.Report
    ]
  )
end
