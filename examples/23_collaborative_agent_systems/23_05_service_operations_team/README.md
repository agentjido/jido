# 23_05 Service-operations team

This durable team Flow moves one service request through intake, assignment,
quality review, and correlated human approval.

## What you will learn

- How role Actions share one explicit service-request artifact owner.
- How high-priority work selects a team before quality review.
- How an unrelated approval is rejected and the durable Wait remains open.

## Read the code

Read [the role Actions and durable Flow](service_operations.ex).

## Run it

`mix test.examples examples/23_collaborative_agent_systems/23_05_service_operations_team --warnings-as-errors`

Expected result: a high-priority request reaches senior operations, passes
quality review, rejects an unrelated approval, and completes on the correlated
approval.

## Important behavior

The durable Flow is the canonical service-request owner. Role Actions do not
share mutable Agent memory. The request ID correlates approval. A timer gives
the Wait a bounded escalation result.

## Limits

Roles are Actions in one Flow, not independently hosted Agents. The example
does not model team capacity or assignment contention. ETS does not survive
BEAM loss.

## Core Fit and Gaps

Actions, Flow, Wait, Signals, and durable execution compose without a team
orchestration API. Use separate hosted Agents only when a role needs its own
identity, lifecycle, concurrency, or persistence boundary.

## Files

- [Source](service_operations.ex)
- [Tests](service_operations_test.exs)

[Previous: Research and publishing](../23_04_research_publishing_team/README.md)

[Next: Nested organization](../23_06_nested_organization/README.md)
