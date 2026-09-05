> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# Prioritized implementation waves

## Best-effort catalog pass

The original catalog pass added 100 source profiles and local tests. Basic
now uses five SDK integration fixtures; see [current results](basic-results.md). The [implementation results](implementation-results.md) are the current review queue. The waves below remain design context; they are not a claim that every advanced runtime contract is complete.

## Implemented anchors

The current code tree has the Basic SDK integration fixtures, the Workflow
group, the ten LLM SDK fixtures, and `04_runtime/04_02_scheduled_counter`. Keep these examples small.
Extend their failure matrices only when the profile lists the new tested
behavior.

## Wave 1: small architecture probes

Build these examples first. They give fast feedback on the public user model.

### Group A: effect and sequence

This group is implemented.

| Example | Main pressure |
| --- | --- |
| Effectful Weather Lookup | External work in an Action with an injected adapter and retry key |
| Sequential Data Flow | Several Flow steps with one terminal Agent commit |

### Group B: Flow error control

This group is implemented.

| Example | Main pressure |
| --- | --- |
| Conditional Fallback | Typed error routing without partial state |
| Structured Output Repair | Validation, bounded correction, and structured errors |

### Group C: runtime timing and recovery

This group has an implemented burn-in. Burst Buncher and the ReAct failure
matrix pass. Persistent Counter Recovery and Durable Schedule Recovery expose
missing runtime contracts and are marked `failed burn-in`.

| Example | Result | Main pressure |
| --- | --- | --- |
| Burst Buncher | passed | Mailbox order, timer replacement, and batch flush |
| Persistent Counter Recovery | failed burn-in | Snapshot restore passes; conditional durable writes are missing |
| ReAct failure matrix | passed | More tool and model failures |
| Durable Schedule Recovery | failed burn-in | Restore passes; stable occurrence delivery is missing |

### Group D: advanced contract spikes

This group has an implemented burn-in.

| Example | Result | Main pressure |
| --- | --- | --- |
| Human Approval Gate | passed | Plain pending work and a later decision Signal replace a suspended Flow continuation |
| Causal Audit Tree | doesn't work yet | Explicit proof data works; automatic runtime and child lifecycle capture are missing |

Wave 1 must use local deterministic tests. The weather example can have an
optional live HTTP test, but the default test uses a fake adapter.

## Pi extension pressure track

Build these focused examples as part of Waves 1 and 3:

1. Dynamic Tool Catalog
2. Tool Permission Gate
3. Background Job Supervisor
4. Automatic Trace Subscriber
5. Extension Package Lifecycle

Pi puts these concerns in one extension surface because it is an interactive
CLI harness. Jido must keep them as separate contracts. Actions and Flows own
program composition. Directives request runtime changes. Observers receive
events. Runtime capabilities own OTP lifecycle. Do not add one hook that lets a
Plugin intercept and change every part of a Turn.

## Wave 2: product-shaped examples

The SQL assistant, lead qualification, and writer-editor Workflow profiles are
implemented. Build a support email agent, document Q&A, Slack channel agent,
and browser task next in this wave. Keep live service tests separate. These
examples test useful adapters, application-owned conversation state, input
Plugins, structured output, and idempotent external calls.

## Wave 3: runtime and recovery

Build durable schedules, event input recovery, reliable delivery, approval and
resume, streaming progress, and child lifecycle recovery. Complete missing
runtime contracts before the multi-agent showcase work.

## Wave 4: multi-agent systems

Build sequential and concurrent teams, handoff, group chat, research teams,
cluster sharding, nested cells, and large review trees. Use bounded local
fixtures first. Add live models only after the state and delivery tests pass.

## Exit criteria for each wave

- Public boundaries use tagged tuples and structured errors.
- New contracts use Zoi-first schemas.
- One input Signal selects one Action or Flow.
- Agent state commits one time per turn.
- Runtime changes use typed Directives or Plugin capabilities.
- Each irreversible effect has an idempotency rule.
- The default test is deterministic and has no network requirement.
