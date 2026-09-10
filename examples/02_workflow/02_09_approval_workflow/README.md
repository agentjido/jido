# Approval Workflow

A multi-Turn flight Agent searches, selects, approves, and submits one
idempotent booking request.

## What you will learn

- How a Flow and separate commands form a multi-Turn application workflow.
- How approval commits a typed Directive before Plugin dispatch.
- How correlated result Signals complete or fail the booking.

## Read the code

Read [the Agent](approval_workflow.ex), then [the search Flow](search_flow.ex),
[the booking Actions](booking_actions.ex), and
[the booking Plugin](booking_plugin.ex). Read [the ports](ports.ex) before the
[local adapters](support/adapters.ex). Finish with
[the behavior tests](../../../test/examples/02_workflow/02_09_approval_workflow/approval_workflow_test.exs).

For a guided run, open [the Livebook](approval_workflow.livemd). It includes a
Mermaid sequence diagram and uses the same source modules and local adapters.

## Run it

```sh
mix test test/examples/02_workflow/02_09_approval_workflow --include example --seed 0
```

Expected result: a booking succeeds or fails in a later Turn, stale selection
fails, duplicate approval makes one provider call, and stale result Signals
cannot replace terminal state.

## Important behavior

Search and booking adapters are runtime clients in execution context. Portable
state and Directives contain no client PID. Named Actions represent first-class
business stages or stable Signal targets; they are not one-use helper wrappers.

## Limits

The local adapters are deterministic learning fixtures. This example does not
provide durable delivery, provider retry, or recovery after process loss.

## Files

- [Agent](approval_workflow.ex)
- [Search Flow](search_flow.ex)
- [Booking Actions](booking_actions.ex)
- [Booking Plugin and Directive](booking_plugin.ex)
- [Ports](ports.ex)
- [Local support adapters](support/adapters.ex)
- [Guided Livebook](approval_workflow.livemd)
- [Tests](../../../test/examples/02_workflow/02_09_approval_workflow/approval_workflow_test.exs)

Previous: [Executable Continuation](../02_08_executable_continuation/README.md) | Next: [LLM examples](../../03_llm/README.md)
