# 23_03 Manager and worker pool

This manager delegates three correlated tasks to durable worker Agent
Addresses in parallel and reduces completed and failed results into one
canonical manager state.

## What you will learn

- How stable Agent Addresses separate logical workers from current processes.
- How parallel worker Turns keep one task ID per result.
- How one manager owns the ordered result set and isolates one worker failure.

## Read the code

Read [the manager, worker, and pool runner](manager_worker_pool.ex).

## Run it

`mix test.examples examples/23_collaborative_agent_systems/23_03_manager_worker_pool --warnings-as-errors`

Expected result: three workers become active in parallel. Tasks A and C
complete, task B fails, and the manager stores all three ordered outcomes.

## Important behavior

The manager Agent is the canonical result owner. Workers own only their local
completed-task state. Worker calls are separate commits. The application pool
converts one failed worker Turn into an explicit failed result for the manager.

## Limits

The local Task pool is not durable. A coordinator process loss can repeat calls
that were accepted but not yet reduced. Worker task IDs are recorded, but this
version does not reject duplicate execution before the Action runs.

## Core Fit and Gaps

Stable Addresses, AgentServer serialization, and normal application
concurrency compose without a worker-pool API. Durable parallel dispatch needs
an application idempotency rule at the worker boundary.

## Files

- [Source](manager_worker_pool.ex)
- [Tests](manager_worker_pool_test.exs)

[Previous: Specialist pipeline](../23_02_specialist_pipeline/README.md)

[Next: Research and publishing](../23_04_research_publishing_team/README.md)
