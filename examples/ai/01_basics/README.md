# AI basics

These lessons add one feature at a time to the graph-first Agent contract.

1. [Basic Agent](01_01_basic_agent/README.md)
2. [Action and Flow tools](01_02_tool_flow/README.md)
3. [Structured output](01_03_structured_output/README.md)
4. [Limits and tool policy](01_04_controls/README.md)
5. [Streaming](01_05_streaming/README.md)
6. [Request contract](01_06_request_contract/README.md)
7. [Core composition](01_07_core_composition/README.md)
8. [Model defaults](01_08_model_helpers/README.md)
9. [JSON Agent](01_09_json_agent/README.md)

All tests are offline. They replace only the inference client result.

```sh
mix test.examples test/examples/ai/01_basics --warnings-as-errors
```
