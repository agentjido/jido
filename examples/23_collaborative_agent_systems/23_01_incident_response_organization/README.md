# 23_01 Incident-Response Organization

This declared Agent organization triages one incident, contains it, waits for
human approval, isolates one failed audit team, removes its full subtree, and
restores the coordinator under the same logical Agent Address.

## What you will learn

- How root, triage, remediation, audit, and nested analyst Agents own separate
  state and commits.
- How explicit connections route one Signal journey through the organization.
- How a failed team does not roll back committed work in another team.
- How logical Agent identity survives replacement of its hosting process.

## Read the code

Read [the organization definitions](incident_response.ex), then read the
[recovery and failure-isolation test](incident_response_test.exs).

## Run it

`mix test.examples examples/23_collaborative_agent_systems/23_01_incident_response_organization --warnings-as-errors`

Expected result: six Agents become resident. The injected audit failure leaves
that Agent at revision zero. Remediation reaches the coordinator, approval
resolves the incident, root shutdown removes all six processes, and activation
restores resolved state with a new activation ID.

## Important behavior

The coordinator is the canonical owner of incident status. Team topology
describes ownership and delivery. It does not create shared memory. Each Agent
commits a separate Turn. The coordinator snapshot does not contain child
snapshots. A saved root is not one coordinated checkpoint of all team state.

## Limits

Local topology delivery is best effort. The audit failure is observed through
its unchanged revision and continued process life; the coordinator does not
receive an automatic failure Signal. ETS survives process replacement but not
BEAM loss. The example removes the complete root subtree, not one selected
department while the root remains active.

## Core Fit and Gaps

Declared topology, Signals, AgentServer commits, persistence, and stable Agent
references compose into a real organization. The missing automatic child
failure notification is an application policy choice; a Plugin or supervisor
observer can turn it into a domain Signal when required.

- Logical owner: `incident-coordinator` stable Agent Address.
- Process owner: the current coordinator AgentServer activation.
- Canonical state owner: persisted coordinator Agent state.
- Commit point: each AgentServer Turn commits independently.
- Persisted data: coordinator and team Agent state in separate records.
- Retry boundary: each Signal delivery and Agent Turn.
- Idempotency rule: the incident ID correlates triage, remediation, and
  approval; this first version does not deduplicate a repeated report.
- Injected failure: audit team Action failure.
- Recovery result: remediation and approval complete; coordinator state
  restores under a new activation ID.
- Limits and non-guarantees: no organization-wide transaction or child
  checkpoint exists.

## Files

- [Source](incident_response.ex)
- [Tests](incident_response_test.exs)

[Next: Specialist pipeline](../23_02_specialist_pipeline/README.md)
