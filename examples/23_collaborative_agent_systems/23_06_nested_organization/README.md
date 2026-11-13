# 23_06 Nested organization

This declared company starts two departments, four teams, and eight workers.
One worker failure is isolated, root snapshots stay bounded, and root shutdown
removes the complete owned subtree.

## What you will learn

- How nested topology expresses company, department, team, and worker
  ownership.
- How one worker failure does not change a sibling worker.
- Why a root snapshot is not a recursive organization checkpoint.

## Read the code

Read [the four-level topology](nested_organization.ex), then read the
[lifecycle test](nested_organization_test.exs).

## Run it

`mix test.examples examples/23_collaborative_agent_systems/23_06_nested_organization --warnings-as-errors`

Expected result: 15 Agents become resident. One worker stays at revision zero
after failure, one sibling commits revision one, and root shutdown returns the
resident count to zero.

## Important behavior

Topology describes ownership and local delivery, not shared memory. Every
worker has separate state and commits. The public root snapshot does not embed
child state, so snapshot size does not grow with the complete subtree.

## Limits

The example proves complete root-subtree shutdown. It does not remove one
selected declared department while keeping the root active. Static declared
topology has no public runtime operation for that mutation.

## Core Fit and Gaps

Declared topology and OTP supervision compose cleanly for a fixed organization
shape. A public, controlled removal operation would be needed to teach dynamic
declared-subtree removal. Until that contract exists, the example does not call
private topology functions or claim support.

## Files

- [Source](nested_organization.ex)
- [Tests](nested_organization_test.exs)

[Previous: Service operations](../23_05_service_operations_team/README.md)
