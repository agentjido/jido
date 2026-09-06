# Tool Loop

- **ID:** `03_04_tool_loop`
- **Status:** implemented
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** local deterministic SDK integration
- **Tests:** 11

## SDK obligation

Flow Dispatch and continuation carry model/tool rounds to one terminal commit.

## Acceptance cases

- One Signal runs the complete effectful ReAct Flow and commits once.
- A failed Flow keeps Agent state but does not undo completed effects.
- Several tool calls remain inside one committed Turn.
- An unknown tool fails without a commit.
- A tool error preserves its completed model effect but does not commit.
- Malformed model output fails before any tool effect.
- The application step budget bounds recursive tool use.
- A provider timeout fails without a commit.
- Cancelling the active Turn stops model work and keeps Agent state.
- Intermediate rounds expose prior state and the final transcript commits once.
- The SDK continuation bound is separate from the model-step budget.

## Implementation and evidence

- [Source](../../../../examples/03_llm/03_04_tool_loop/react_agent.ex)
- [Integration tests](../../../../test/examples/03_llm/03_04_tool_loop/react_agent_test.exs)
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
