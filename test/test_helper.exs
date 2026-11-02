Mimic.copy(ReqLLM)
Mimic.copy(Jido.AITest.Tools.Add)

ExUnit.start(capture_log: true)

{_result, _expected_warnings} =
  Code.with_diagnostics(fn ->
    Code.require_file("support/fixtures/action/missing_callbacks.exs", __DIR__)
  end)

ExUnit.configure(
  exclude: [
    :integration,
    :skip,
    :flaky,
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
)
