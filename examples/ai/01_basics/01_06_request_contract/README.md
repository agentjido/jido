# 01_06 Request contract

Use `preflight/1` to validate input and compile the root Flow without model or
tool work. It reports the normalized request, declared tools, and workflow.
The request tool policy selects what the model can use at run time.

The [tests](../../../../test/examples/ai/01_basics/01_06_request_contract/request_contract_test.exs)
check preflight limits, local tool contracts, request and run IDs, usage, and
ordered Session entries.

```sh
mix test.examples test/examples/ai/01_basics/01_06_request_contract --warnings-as-errors
```

Previous: [Streaming](../01_05_streaming/README.md) | Next: [Core composition](../01_07_core_composition/README.md)
