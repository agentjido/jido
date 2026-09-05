# Grounded Answer

- **ID:** `03_06_grounded_answer`
- **Status:** implemented
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** local deterministic SDK integration
- **Tests:** 3

## SDK obligation

Retrieve evidence, generate an answer, and validate citation identity, revision, and page before commit.

## Acceptance cases

- Retrieval and generation receive exact inputs before validated provenance commits.
- No evidence makes zero model calls; bad identity, revision, or page cannot replace prior state.
- Resolver receives committed history and web search requires explicit permission.

## Implementation and evidence

- [Source](../../../../lib/examples/03_llm/03_06_grounded_answer/grounded_answer.ex)
- [Integration tests](../../../../test/examples/03_llm/03_06_grounded_answer/grounded_answer_test.exs)
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
