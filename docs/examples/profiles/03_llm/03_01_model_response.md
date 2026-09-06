# Model Response

- **ID:** `03_01_model_response`
- **Status:** implemented
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** local deterministic SDK integration
- **Tests:** 4

## SDK obligation

One typed response, transient client context, selected persisted fields, and explicit fallback policy.

## Acceptance cases

- Exact input and selected output cross direct and live boundaries.
- Bad input makes no call and bad output preserves a prior commit.
- Transient fallback records both calls; auth and malformed fallback preserve state.
- Execution deadline terminates a blocked provider worker.

## Implementation and evidence

- [Source](../../../../examples/03_llm/03_01_model_response/model_response.ex)
- [Integration tests](../../../../test/examples/03_llm/03_01_model_response/model_response_test.exs)
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
