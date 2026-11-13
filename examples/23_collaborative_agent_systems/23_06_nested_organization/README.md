# 23_06 Nested organization

This declared company starts two departments, four teams, and eight workers.
One worker failure is isolated, root snapshots stay bounded, and one selected
department can stop while the company root stays active.

## What you will learn

- How nested topology expresses company, department, team, and worker
  ownership.
- How one worker failure does not change a sibling worker.
- How `Jido.AgentServer.remove_topology_member/4` removes one declared member
  slot and all of its descendants.
- Why a root snapshot is not a recursive organization checkpoint.

## Read the code

Read [the four-level topology](nested_organization.ex), then read the
[lifecycle test](nested_organization_test.exs).

## Run it

`mix test.examples examples/23_collaborative_agent_systems/23_06_nested_organization --warnings-as-errors`

Expected result: 15 Agents become resident. One worker stays at revision zero
after failure, one sibling commits revision one, one seven-Agent department
subtree stops, and the company root and other department stay active.

## Important behavior

Topology describes ownership and local delivery, not shared memory. Every
worker has separate state and commits. The public root snapshot does not embed
child state, so snapshot size does not grow with the complete subtree.

`Company.remove_department/3` uses the public AgentServer operation. Removal
closes admission for the selected subtree. It finishes accepted Turns by
default and then stops descendants before the department. A repeated removal
returns `:ok`. A partial timeout keeps removal pending, and the caller can
repeat the operation to continue cleanup.

## Limits

Removal applies only to the current root activation. It does not change the
static Agent definition or delete durable child records. A replacement root
activation creates the declared department again. Saved child state is
restored when persistence is enabled. The parent snapshot is not an atomic
checkpoint for all children.

## Core Fit and Gaps

Declared topology and OTP supervision compose cleanly for startup, failure
isolation, selected-subtree removal, and complete root shutdown. The example
uses only the public AgentServer API. Applications that need membership changes
that survive root replacement must use a new static definition or separately
owned dynamic Agents.

## Files

- [Source](nested_organization.ex)
- [Tests](nested_organization_test.exs)

[Previous: Service operations](../23_05_service_operations_team/README.md)
