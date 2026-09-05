# Output Repair

- **ID:** `03_07_output_repair`
- **Status:** implemented
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** local deterministic SDK integration
- **Tests:** 3

## SDK obligation

Flow Iterate carries validation feedback through at most three model attempts.

## Acceptance cases

- Valid first output makes one call and invalid output sends specific feedback.
- Last allowed repair succeeds; exhaustion makes exactly three calls and preserves it.
- Provider failure is not an automatic repair.

## Implementation and evidence

- [Source](../../../../lib/examples/03_llm/03_07_output_repair/output_repair.ex)
- [Integration tests](../../../../test/examples/03_llm/03_07_output_repair/output_repair_test.exs)
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
