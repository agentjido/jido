# 23_04 Research and publishing team

This CrewAI-style team runs Researcher Agents in parallel, reduces evidence
through one Analyst Agent, drafts through a Writer Agent, and applies one
bounded Critic revision.

## What you will learn

- How roles remain normal Agent definitions instead of a second role runtime.
- How the coordinator owns canonical mission state and one evidence reducer.
- How partial researcher failure and critic revision stay bounded.

## Read the code

Read [the five role and coordinator modules](research_publishing_team.ex).

## Run it

`mix test.examples examples/23_collaborative_agent_systems/23_04_research_publishing_team --warnings-as-errors`

Expected result: two parallel evidence records become one finding and an
approved revision 1 draft. With one researcher failure, the remaining evidence
still completes the mission.

## Important behavior

The coordinator return value is the canonical mission artifact. Researchers
do not share mutable memory. The Analyst is the only evidence reducer. The
Critic can request at most one revision.

## Limits

These Agents run through pure `Agent.cmd/3`; their processes and state are not
persisted. The local Task pool can repeat work after coordinator loss. There is
no human publication approval in this lesson.

## Core Fit and Gaps

Pure Agents, Signals, replies, and bounded application concurrency are enough
for a CrewAI-style local team. Durable missions need stable Agent references,
idempotent role inputs, and a persisted coordinator, as shown by the other
collaboration examples.

## Files

- [Source](research_publishing_team.ex)
- [Tests](research_publishing_team_test.exs)

[Previous: Manager and worker pool](../23_03_manager_worker_pool/README.md)

[Next: Service operations](../23_05_service_operations_team/README.md)
