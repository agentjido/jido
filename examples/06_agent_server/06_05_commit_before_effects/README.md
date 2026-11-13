# 06_05 Commit Before Effects

One Turn commits state and then injects a failing Plugin delivery effect.

## What you will learn

- Where the AgentServer commit point occurs.
- How a later effect failure stays visible without rolling back state.

## Read the code

Read [the Agent, Directive, and Plugin](commit_before_effects.ex), then read
[the failure drill](commit_before_effects_test.exs).

## Run it

`mix test.examples examples/06_agent_server/06_05_commit_before_effects --warnings-as-errors`

Expected result: Agent revision 1 contains `count: 1`; the delivery effect
fails; the committed snapshot remains unchanged.

## Important behavior

- Logical owner: the Counter Agent.
- Process owner: AgentServer.
- Canonical state owner: the Counter Agent record.
- Commit point: AgentServer revision 1 before Plugin dispatch.
- Persisted data: none; this is an in-memory commit proof.
- Retry boundary: no retry in this example.
- Idempotency rule: none; the failed delivery is not repeated.
- Injected failure: Plugin dispatch returns an execution error.
- Recovery result: committed state remains available for a later Turn.

## Limits

This example does not claim exactly-once effect delivery. It does not retry or
compensate for the failed effect. An Action that performs I/O before it returns
is outside this commit-order guarantee.

## Core Fit and Gaps

The public snapshot proves state was committed before the Plugin observed it.
Public semantic telemetry reports the later effect failure. The status value
shows pending effects while work is active, but it does not retain the last
effect outcome after the Agent becomes idle. Applications that need a queryable
effect ledger must own one in domain or Plugin state.

## Files

- [Agent, Directive, and Plugin](commit_before_effects.ex)
- [Failure drill](commit_before_effects_test.exs)
