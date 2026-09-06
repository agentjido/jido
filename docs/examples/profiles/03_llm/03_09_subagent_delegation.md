# Subagent Delegation

- **ID:** `03_09_subagent_delegation`
- **Status:** implemented
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** local deterministic SDK integration
- **Tests:** 6

## SDK obligation

Spawn a real child Agent, transfer client context explicitly, and correlate result and failure Signals.

## Acceptance cases

- Portable Directives start a real child; independent model work follows the pending commit.
- Stale and duplicate results cannot complete another request; duplicate IDs make no model call.
- Invalid specialist selection starts no child and performs no specialist effect.
- Child model failure becomes a correlated result and a new request can succeed.
- Child process loss cannot leave the parent request pending.
- The child's execution deadline ends blocked model work and reports failure.

## Implementation and evidence

- [Source](../../../../examples/03_llm/03_09_subagent_delegation/subagent_delegation.ex)
- [Integration tests](../../../../test/examples/03_llm/03_09_subagent_delegation/subagent_delegation_test.exs)
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

## Child Agent boundary

`Jido.Examples.LLMSubagentDelegation` selects one approved role, `researcher`
or `reviewer`, for each request. The same child Agent definition serves both
roles. At most one request is active in the parent. This example adds child
lifecycle and separate commits; Parallel Tools already covers fan-out.

The parent emits SpawnAgent and a portable Work Directive after it commits
`:working`. A process-free Plugin calls the child with a work Signal and an
explicit specialist client in caller context. The child commits its checked
answer and emits a result Signal to its parent. The parent accepts only the
current request/tag pair, records the result, and stops the temporary child.
Child execution has a separate one-second deadline. Model failure and child
process loss produce a failed result. The parent can accept another request.

The initial call returns the pending parent state. Completion occurs in a later
Turn. A stale result is a successful no-op and can advance the commit revision.
Duplicate request IDs are rejected before a model call. These are application
correlation rules, not authentication or a transaction across Agents. Durable
recovery, failure during child startup, and concurrent subagent trees are not
claims of this fixture.
