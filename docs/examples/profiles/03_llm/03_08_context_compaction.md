# Context Compaction

- **ID:** `03_08_context_compaction`
- **Status:** implemented
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** local deterministic SDK integration
- **Tests:** 2

## SDK obligation

Compact committed history and retain recent and queued messages under an explicit byte limit.

## Acceptance cases

- Compaction reads committed history; queued messages survive and enter the next model input once.
- Fact loss, malformed summary, and byte overflow preserve committed messages.

## Implementation and evidence

- [Source](../../../../examples/03_llm/03_08_context_compaction/context_compaction.ex)
- [Integration tests](../../../../test/examples/03_llm/03_08_context_compaction/context_compaction_test.exs)
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
