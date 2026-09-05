# Parallel Tools

- **ID:** `03_05_parallel_tools`
- **Status:** implemented
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** local deterministic SDK integration
- **Tests:** 5

## SDK obligation

Validate a complete tool plan, run concurrent Actions with Map, and retain call-ID order.

## Acceptance cases

- Two real workers overlap; reverse completion retains call order.
- A finite plan obeys the serial limit.
- Complete plan admission rejects duplicate IDs, unknown names, and bad arguments before any effect.
- Empty tools and collected item errors reach the model with stable correlation.
- Cancellation terminates all active tools and preserves a prior commit.

## Implementation and evidence

- [Source](../../../../lib/examples/03_llm/03_05_parallel_tools/parallel_tools.ex)
- [Integration tests](../../../../test/examples/03_llm/03_05_parallel_tools/parallel_tools_test.exs)
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

Map collect mode in jido_action beta.4 returns message-only item errors. The example uses the admitted plan position to retain call IDs. Structured error adoption remains tracked in [v3 #18](https://github.com/mikehostetler/jido_v3/issues/18).
