# Factory orchestrator plan

## Target

Build a system that accepts a goal, creates an explicit plan, assigns work to
department heads, records evidence, and reports progress through the conversation
Agent. The factory continues while the user is away. Its saved plan determines
the next action.

The current third example implements the first working structure. It runs four
heads with a fixed dependency graph. The items below are planned extensions,
not claims about the current code.

## Agent ownership

```text
System owner
  Conversation
  Factory orchestrator
    Research head
      Retrieval and analysis workers
    Design head
      Architecture and interface workers
    Engineering head
      Implementation workers
    Quality head
      Test and review workers
    Delivery head
      Packaging and release workers
    Operations head
      Recovery and monitoring workers
```

The orchestrator owns mission status, plan revisions, dependencies, capacity,
budgets, approvals, and accepted artifact references. Each department head owns
its work queue, worker capacity, retries, and department results. Worker Agents
own bounded work. Large content belongs in an artifact store; Agent state holds
references, hashes, versions, and short summaries.

The System Agent owns lifecycle and conversation routing. It does not make
department decisions. The factory must have a stable identity and an owner
that survives a chat session. If factory lifetime must exceed the System
Agent's lifetime, start the factory as an independent instance-supervised Agent.

## Department contracts

| Head | Input | Deliverable | Completion check |
| --- | --- | --- | --- |
| Research | Goal, questions, source policy | Requirements and evidence with source references | Required questions answered or listed as unresolved |
| Design | Requirements and constraints | Design, interfaces, acceptance criteria | Schema validation and required review |
| Engineering | Approved design and work package | Patch or other build artifact | Required checks recorded against the exact revision |
| Quality | Artifact revision and criteria | Findings and a typed verdict | Evidence supports each acceptance result |
| Delivery | Approved artifact and destination | Delivery receipt | Destination confirms the exact artifact |
| Operations | Mission state and runtime health | Recovery decisions and incident records | Lost work is classified before retry |

Start with the four current heads. Add worker Agents when a head needs parallel
work or a separate failure boundary. Add Delivery only when the application has
defined destinations and approval rules. Add Operations when recovery is a
tested contract.

## Plan data

Use Zoi schemas for these records:

- Mission: ID, goal, constraints, status, active plan revision, budget, and
  requested outcome.
- Plan revision: immutable revision ID, parent revision, reason for change,
  steps, dependency edges, acceptance criteria, and approval requirements.
- Step: ID, department, input artifact references, expected output schema,
  dependencies, deadline, retry limit, and external idempotency key.
- Attempt: fresh attempt ID, stable step ID, worker identity, status, start
  time, deadline, result reference, and failure classification.
- Artifact: ID, content hash, format, revision, producer attempt, storage
  reference, and validation evidence.
- Approval: decision ID, agent identity, allowed action, artifact or plan
  revision, expiry, and decision.

A plan validator rejects cycles, unknown departments, missing dependencies,
unbounded steps, and unsupported effects before any work starts. An LLM can
propose a plan. Application code validates and commits the accepted revision.

## Control loop

1. Accept a goal with a stable request ID. Commit the mission before planning.
2. Start a bounded planning request. Validate its result as a separate turn.
3. Commit the plan revision. Request any required approval through a Signal.
4. Select ready steps whose dependencies and approvals are satisfied.
5. Reserve capacity and budget in the same commit as attempt intent.
6. Start department work through Directives after that commit.
7. Accept results only for the active plan revision and attempt.
8. Validate the artifact, record evidence, and release capacity.
9. Start newly ready work, request a decision, or complete the mission.

Each turn is short. Waiting for a model, worker, approval, or external service
happens outside the orchestrator's active turn. Independent departments can
run concurrently. The orchestrator has explicit global and department limits.

## Signal protocol

Keep all communication between Agents on Signals. Proposed Signal types:

| Direction | Signals |
| --- | --- |
| Conversation to factory | `factory.goal.submit`, `factory.goal.change`, `factory.status.request`, `factory.pause`, `factory.resume`, `factory.cancel`, `factory.approval.decide` |
| Factory to head | `department.work.assign`, `department.work.cancel`, `department.status.request` |
| Head to factory | `department.work.accepted`, `department.work.progress`, `department.work.completed`, `department.work.failed`, `department.input.required` |
| Factory to conversation | `factory.progress`, `factory.input.required`, `factory.approval.required`, `factory.completed`, `factory.failed` |

Every work event carries mission, plan revision, step, attempt, and event IDs.
Progress events can be combined to reduce volume. Completion and failure events
need acknowledgement and retry. A status query returns committed state and its
revision. The chat transcript is not the source of truth for mission state.

## Change, pause, cancel, and retry

Changing a goal creates a new plan revision. Keep accepted artifacts only when
their inputs remain valid. Invalidate dependent steps when an input changes.
Reject results from superseded attempts.

Pause stops new admission and can let active work reach a checkpoint. Cancel
records terminal intent first, then requests worker cancellation. Define which
external operations can be cancelled and which can only be reconciled later.
Never infer external rollback from a process exit.

Retry keeps the stable work and external idempotency keys but uses a fresh
attempt ID. Retry only classified transient failures. A timeout or lost reply
can leave the external outcome unknown; check the destination before retrying.

## Persistence and recovery

Persist mission and plan state with pending effect intent. Use the existing
recoverable-delivery, pending-job-recovery, and durable-scheduling examples as
starting points. On restart, reconcile each pending attempt with its department
and external destination. A saved `running` value is not proof of a live task.

Keep provider credentials and client processes outside portable state. Rebuild
clients from runtime configuration after restore. Recover stable Agent IDs and
department ownership before admitting new work. Test crash windows between
commit, dispatch, external completion, result delivery, and acknowledgement.

## Implementation sequence

| Stage | Work | Exit check |
| --- | --- | --- |
| 1 — implemented | Direct ReqLLM conversation | History and failures behave correctly through the real HTTP encoding path |
| 2 — implemented | Three main Agents and temporary item workers | A one-second FIFO queue starts one worker at a time; tools inspect state; feedback commits while the model is busy |
| 3 — implemented | Four heads and a fixed plan | Parallel roots, dependency order, pause, cancellation, and failure tests pass |
| 4 | Typed mission and plan records; validated dynamic plans | Invalid plans start no work; revision changes reject stale results |
| 5 | Department queues, bounded workers, and artifact storage | Limits hold under load; artifact evidence matches input revisions |
| 6 | Durable intent, acknowledgements, and recovery | Process and VM crash tests resume or classify every pending attempt |
| 7 | Human decisions, budgets, and delivery | No controlled effect starts without the matching decision and budget |
| 8 | Operations, remote placement, and load tests | Reconciliation, ownership, overload behavior, and failure reporting are proven |

Keep each stage runnable as a separate numbered example. Expand the factory
through small contracts and tested runtime boundaries.
