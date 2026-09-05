# Tool Call

- **ID:** `03_03_tool_call`
- **Status:** implemented
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** local deterministic SDK integration
- **Tests:** 4

## SDK obligation

An approved name resolves to a typed Action; invalid input stops before tool effects.

## Acceptance cases

- A typed tool result retains its call ID in the final model input.
- Unknown tools, bad arguments, and denied operations make zero tool calls.
- SDK tool schema prevents direct invalid execution.
- Tool failure and late answer failure preserve prior state but keep external effects.

## Implementation and evidence

- [Source](../../../../lib/examples/03_llm/03_03_tool_call/tool_call.ex)
- [Integration tests](../../../../test/examples/03_llm/03_03_tool_call/tool_call_test.exs)
- [LLM suite and results](../../llm-results.md)

The tests use real Agents, Signals, Actions, Exec, and Server commits. Flows
and Directives are real where this fixture uses them. Only external services
use scripted replies. Tests record actual inputs and completed calls.

Model and tool clients enter through transient caller context. Signals carry
portable application values. A failed Turn preserves prior Agent state; it
does not undo completed external work. Validation and tool permission rules
belong to the application. These tests do not measure model quality or live
provider compatibility.

## Earlier domain examples

See the [research archive and replacement map](../../archive/llm/README.md).
