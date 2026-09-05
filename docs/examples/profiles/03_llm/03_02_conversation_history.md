# Conversation History

- **ID:** `03_02_conversation_history`
- **Status:** implemented
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** local deterministic SDK integration
- **Tests:** 2

## SDK obligation

Actual history across Turns, duplicate rejection, and restore with a fresh client.

## Acceptance cases

- Two Turns use actual history; duplicates and errors preserve it.
- Persisted history restores and the next Turn uses a fresh client.

## Implementation and evidence

- [Source](../../../../lib/examples/03_llm/03_02_conversation_history/conversation_history.ex)
- [Integration tests](../../../../test/examples/03_llm/03_02_conversation_history/conversation_history_test.exs)
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
