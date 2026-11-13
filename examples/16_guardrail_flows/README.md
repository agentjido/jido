# 16 Guardrail Flows

These examples put explicit policy Actions around model, tool, and human
review boundaries. They use normal Jido Flows. Jido does not apply hidden
guardrail middleware.

## Examples

1. [Input and output policy](16_01_input_output_policy/README.md) checks PII,
   prompt injection, moderation, and model output. It compares fail-open and
   fail-closed behavior and produces an audit record.
2. [Tool boundary policy](16_02_tool_boundary_policy/README.md) checks a tool
   call before execution and checks its result before model reuse.
3. [Human review](16_03_human_review/README.md) uses a durable Wait for an
   explicit approval, denial, or timeout decision.

The tests are deterministic and offline. They do not call a model provider,
moderation service, PII service, or external tool.
