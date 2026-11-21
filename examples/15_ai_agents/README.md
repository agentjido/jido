# 15 AI Agents

These lessons add one model-backed feature at a time to the normal Agent
contract. All inference is deterministic and offline.

1. [Basic Agent](15_01_basic_agent/README.md)
2. [Action and Flow tools](15_02_tool_flow/README.md)
3. [Structured output](15_03_structured_output/README.md)
4. [Limits and tool policy](15_04_controls/README.md)
5. [Streaming](15_05_streaming/README.md)
6. [Request contract](15_06_request_contract/README.md)
7. [Core composition](15_07_core_composition/README.md)
8. [Model defaults](15_08_model_helpers/README.md)
9. [JSON Agent](15_09_json_agent/README.md)
10. [Capability preflight](15_10_capability_preflight/README.md)
11. [Multimodal content](15_11_multimodal_content/README.md)
12. [Media operations](15_12_media_operations/README.md)
13. [Skills and ToolSources](15_13_skills_and_tool_sources/README.md), including
    the offline MCP boundary.
14. [Offline testing](15_14_offline_testing/README.md)

All tests are offline. They use deterministic inference clients and local
fixtures. They do not call a model provider or MCP server.

```sh
mix test.examples examples/15_ai_agents --warnings-as-errors
```
