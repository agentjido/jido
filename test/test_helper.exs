# Load the local provider catalog before concurrent test compilation starts.
# This reads packaged metadata and makes no provider request. Otherwise the
# first timed HTTP/SSE test can wait behind code loading for unrelated tests.
{:ok, _model} = ReqLLM.model("anthropic:claude-haiku-4-5")

ExUnit.start()

# Focused schema and snapshot probes: mix test --only basic_contract
# All examples, including application scenarios: mix examples
ExUnit.configure(exclude: [:skip, :flaky, :example])
