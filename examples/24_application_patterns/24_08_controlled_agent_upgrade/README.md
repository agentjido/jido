# 24_08 Controlled Agent Upgrade

This application quiesces a durable Agent, replaces its definition and state
schema, resumes under the same logical Address, survives one failed migration,
and rolls back to the prior definition.

## What you will learn

- How quiesce closes admission before a controlled upgrade.
- How `Jido.upgrade_agent/4` applies an explicit snapshot migration while the
  Agent is inactive.
- How failure restores the last valid durable record.
- How rollback is another explicit, tested migration.

## Read the code

Read [the two definitions and three migration Actions](controlled_agent_upgrade.ex),
then read the [lifecycle test](controlled_agent_upgrade_test.exs).

## Run it

`mix test.examples examples/24_application_patterns/24_08_controlled_agent_upgrade --warnings-as-errors`

Expected result: V1 count 3 migrates to V2 total 3, V2 increments to 4, the
injected migration fails without changing V2, and V3 restores the V1 state
shape with count 4.

## Important behavior

The stable Agent Address is the logical identity. Each successful upgrade
replaces the hosting activation. The durable record is the canonical state
owner. Admission is closed before migration. A failed migration does not commit
candidate state. Rollback uses a declared reverse migration, not a process
restart. The saved definition changes, but the Agent origin module stays stable.
The V2 compiled module supplies a trusted definition template; it does not
become the persisted origin module. Rollback is a new, higher definition
version with earlier behavior. It does not decrease the version number.

## Limits

The schema change is small and uses one ETS store. The example does not migrate
child Agents, external resources, or a distributed fleet. A saved parent does
not imply one coordinated child checkpoint.

## Core Fit and Gaps

Public quiesce, stable Addresses, persistence snapshots, migration Actions,
and `Jido.upgrade_agent/4` provide the complete control path. Upgrade failure
and rollback are explicit and tested. The first implementation attempt changed
the origin module. Jido rejected it with `:upgrade_identity`; the working path
keeps the origin and replaces the saved definition data.

- Logical owner: stable account Agent Address.
- Process owner: current AgentServer activation.
- Canonical state owner: durable Agent record.
- Commit point: successful persistence upgrade.
- Persisted data: complete Agent definition, state, version, and references.
- Retry boundary: one explicit migration Action.
- Idempotency rule: each migration accepts only its declared source version.
- Injected failure: migration Action error after quiesce.
- Recovery result: last V2 state reactivates unchanged, then reverse migration
  restores the V1 state shape as V3.
- Limits and non-guarantees: no fleet-wide or child-graph transaction.

## Files

- [Source](controlled_agent_upgrade.ex)
- [Tests](controlled_agent_upgrade_test.exs)

[Previous: Recoverable External Delivery](../24_07_recoverable_external_delivery/README.md)
