# 16_03 Human review

This durable Flow waits for an approved, denied, or expired policy decision and
completes once after an accepted Signal.

## What you will learn

- How a normal Flow Selection expresses a human review boundary.
- How `Jido.Durable` saves the Wait and resumes it from a correlated Signal.
- How a repeated approval returns the same completed durable status.

## Read the code

Read [the durable review Flow](human_review.ex) first.

## Run it

`mix test.examples examples/16_guardrail_flows/16_03_human_review --warnings-as-errors`

Expected result: the Flow enters `:waiting`, accepts one correlated approval,
returns `:approved`, and reports the same completion for a duplicate approval.

## Important behavior

The request ID correlates the approval to the Wait. The persisted execution
record is the canonical state owner. The Jido process hosts the durable
execution, but process identity is not the review identity. Completion is the
commit point. A repeated Signal returns the completed status and cannot change
the committed result.

## Limits

ETS provides deterministic local persistence. It does not survive BEAM loss.
The example does not authenticate the reviewer or prove delivery from a user
interface. The parent execution record is not a coordinated checkpoint of an
external approval system.

## Core Fit and Gaps

Flow Selection, Signals, and `Jido.Durable` compose without a new human-review
API. The application owns reviewer authentication and its public audit view.
The duplicate Signal returns the completed durable status. Applications that
need a separate duplicate acknowledgement must define that response at their
delivery boundary.

- Logical owner: durable review reference.
- Process owner: the named Jido instance.
- Canonical state owner: the persisted durable execution record.
- Commit point: saved completed execution.
- Persisted data: Flow input, execution progress, Wait, accepted Signal, and
  result.
- Retry boundary: Signal delivery to one Wait ID.
- Idempotency rule: one Wait accepts one matching decision.
- Injected failure: duplicate approval after completion.
- Recovery result: the first result remains complete and unchanged.
- Limits and non-guarantees: ETS does not survive BEAM loss and reviewer
  identity is not authenticated.

## Files

- [Source](human_review.ex)
- [Tests](human_review_test.exs)

[Previous: Tool boundary policy](../16_02_tool_boundary_policy/README.md)
