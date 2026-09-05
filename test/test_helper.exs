# Load the local provider catalog before concurrent test compilation starts.
# This reads packaged metadata and makes no provider request. Otherwise the
# first timed HTTP/SSE test can wait behind code loading for unrelated tests.
{:ok, _model} = ReqLLM.model("anthropic:claude-haiku-4-5")

ExUnit.start()

# Focused schema and snapshot probes: mix test --only basic_contract
# Basic SDK integration suite: mix test --include integration test/examples/01_basic
ExUnit.configure(exclude: [:skip, :flaky, :example, :integration])
