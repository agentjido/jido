# 23_02 Specialist pipeline

This pure pipeline hands one mission from a classifier Agent to a diagnostician
Agent and then to a responder Agent through correlated reply data.

## What you will learn

- How separate Agent definitions can run through `Agent.cmd/3` without a
  process.
- How one mission ID follows every handoff and artifact.
- How a failed specialist stops the next handoff and returns no later artifact.

## Read the code

Read [the three Agents and coordinator function](specialist_pipeline.ex).

## Run it

`mix test.examples examples/23_collaborative_agent_systems/23_02_specialist_pipeline --warnings-as-errors`

Expected result: the successful mission returns classification, diagnosis, and
response artifacts. An injected diagnosis failure stops before response.

## Important behavior

Each Agent returns a complete immutable candidate. The application function is
the logical owner of the mission result. There is no process or persistence in
this pure example.

## Limits

The three Agent updates are not one transaction. A caller must persist each
candidate if it needs recovery. Pure execution does not provide admission,
serialization, or post-commit effects.

## Core Fit and Gaps

Pure Agent execution and correlated reply Signals compose cleanly for a local
specialist pipeline. A reply selector does not disable default state mapping,
so each route selects both its complete candidate state and its reply. The
[route guide](../../../guides/agents/build-agent-routes.livemd#select-state-and-a-reply)
states this rule. The example does not need a role or task orchestration API.

## Files

- [Source](specialist_pipeline.ex)
- [Tests](specialist_pipeline_test.exs)

[Previous: Incident response](../23_01_incident_response_organization/README.md)

[Next: Manager and worker pool](../23_03_manager_worker_pool/README.md)
