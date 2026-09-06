# Application examples

These ten examples combine Agents, Plugins, Signals, Directives, Flows, child
Agents, and persistence. Source files are in this directory. The matching
[tests](../../test/examples/08_applications) use the single `:example` tag.

Run them from the repository root:

```sh
mix test test/examples/08_applications --include example --seed 0
```

`mix examples` runs these tests and all other example tests. Default `mix test`
skips them. The Agent declarations use Spark `agent` and `routes` blocks.
The modules compile from `.ex` source files; test files contain the assertions.

Start with [Basic](../01_basic/README.md) and
[Workflow](../02_workflow/README.md) for smaller examples. Keep focused core
contract tests in `test/jido/`. Add each application assertion to one matching
file under `test/examples/08_applications`.

## Current Scenarios

- `audit`: A Flow commits Agent and Plugin state only after successful work.
- `coordinator`: A Flow commits Agent-owned delegation history, starts a child Agent, sends
  work, receives a reply, and receives a scheduled timeout.
- `elastic_group`: A persistent controller, environment, and monitor scale
  Workers from two to ten, reclaim failed work, and drain back to two.
- `fixed_group`: A controller owns an environment and three Workers that
  coordinate targeted work and results through a Signal Bus.
- `inbox`: An input Plugin handles a burst, removes duplicate events, and
  continues after its runtime restarts.
- `identity`: A live Plugin verifies private-key control with a trusted public
  key, rejects replay and forgery, and signs a correlated reply.
- `purpose_loop`: Scheduled finite turns continue without client input, reject
  duplicate ticks, restore committed work, and drain without runtime leaks.
- `react`: One execution chain runs a tool loop, commits Agent-owned message
  history once, and handles a scheduled follow-up Signal. Later Turns receive
  prior history; a failed Turn preserves the previous commit.
- `secure_signal`: Identity verifies an encrypted Signal before secure
  admission decrypts its `secure` data. Replies are encrypted before they are
  signed.
- `subscription`: Committed Plugin state repairs external runtime state after a
  dispatch failure and a runtime restart.

## Test Rules

- Test behavior through public APIs.
- Use one complete scenario for each test when practical.
- Assert the committed Agent state before you assert later runtime effects.
- Use `JidoTest.Eventually` for asynchronous state and process checks.
- Do not use fixed sleeps to wait for runtime behavior.
- Use unique Agent IDs and process names to prevent test interference.
- Keep single-module validation and error matrices in `test/jido/`.
- Port useful behavior from old examples. Do not restore tests that depend on
  removed Agent, AgentServer, FSM, Pod, Sensor, Memory, or legacy Plugin APIs.

## TODO

### Coordinator and Child Agents

- [ ] Run several jobs at the same time and verify that each reply has the
  correct correlation ID.
- [ ] Aggregate replies from several child Agents without losing or repeating a
  result.
- [ ] Make an early reply cancel or supersede its timeout.
- [ ] Make a timeout produce one terminal result and ignore a late reply.
- [ ] Verify that a child crash and restart does not lose its parent binding or
  pending work ownership.
- [ ] Exercise a three-level Agent hierarchy and verify that results return to
  the root Agent.
- [ ] Verify that pending-job state is empty after success, failure, and timeout.
- [ ] Repeat adopt, orphan, and restart cycles and verify stable parent bindings.

### Signal Order and Trace Data

- [ ] Preserve trace and causation data across parent-to-child and
  child-to-parent Signals.
- [ ] Preserve trace data across emitted and scheduled follow-up Signals.
- [ ] Preserve sender order while a slow Agent turn is active.
- [ ] Verify the order of several emitted Signals from one committed turn.
- [ ] Verify that a loopback Signal observes the state from the turn that
  emitted it.

### Identity and Secure Signals

- [x] Verify a Signal signature with a trusted public key while the sender
  keeps the private key.
- [x] Reject a forged Signal and a replayed identity nonce before routing.
- [x] Sign an outbound Signal after Jido adds correlation data.
- [x] Verify encrypted inbound data before decrypting the `secure` key.
- [x] Encrypt the outbound `secure` key before identity signs the Signal.
- [x] Keep decrypted secure data in transient Turn context and out of committed
  Agent state.

### Persistence and Recovery

- [ ] Hibernate and thaw an Agent with message history and the Scheduler Plugin.
- [ ] Hibernate and thaw an Agent that uses a custom stateful Plugin.
- [ ] Restore scheduled work without running it twice.
- [ ] Restore child ownership and parent bindings after an Agent restart.
- [ ] Reconcile external Plugin state after a complete Agent restart, not only a
  Plugin runtime restart.
- [ ] Verify recovery when a runtime stops while work is queued or in progress.

### Plugin Failure Cases

- [ ] Verify ordered state reduction for a batch of Plugin Directives.
- [ ] Verify that one dispatch failure stops the remaining runtime effects but
  keeps the committed Agent and Plugin state.
- [ ] Verify that a restarted Plugin runtime reads the latest committed state.
- [ ] Verify behavior when a Plugin runtime is unavailable during Agent start.
- [ ] Verify that an invalid Plugin Directive prevents the complete turn from
  committing.

### Inbox Pressure

- [ ] Increase the burst size and verify ordered processing.
- [ ] Restart the input Plugin while the Agent mailbox has queued Signals.
- [ ] Send duplicate events before and after a Plugin runtime restart.
- [ ] Verify idempotency when two input processes send the same event at the
  same time.
- [ ] Define and test overload behavior for a sustained input burst.

### ReAct Flow

- [ ] Run several tool calls before the final answer.
- [ ] Handle a tool failure without committing a partial conversation.
- [ ] Handle an LLM failure and a bounded retry.
- [ ] Handle a timeout or cancellation during a tool loop.
- [x] Verify that Agent-owned message history commits only once for the complete
  execution chain and is available to later Turns.
- [x] Preserve committed history when the model fails after a tool call.
- [ ] Send two reasoning Signals and verify Agent turn serialization.

### Audit and Subscription

- [ ] Record several audit Directives from one successful turn in order.
- [ ] Verify that each Flow failure phase leaves audit state unchanged.
- [ ] Restart the audit runtime and verify that it restores all committed
  events.
- [ ] Subscribe and unsubscribe in one Directive batch and verify final desired
  state.
- [ ] Restart the subscription runtime after an unsubscribe and verify that the
  removed topic does not return.
- [ ] Repeat reconciliation failures and verify eventual recovery from committed
  desired state.

### Observability

- [ ] Verify bounded Agent and Directive telemetry for one complete integration
  scenario.
- [ ] Verify span completion for successful, failed, timed-out, and cancelled
  turns.
- [ ] Verify that sensitive Signal and Plugin data is not present in telemetry
  metadata.

## Large System Scenarios

These scenarios test coordination between many Agents. Use deterministic local
Actions and fixtures. An external model must not be required for the default
test suite.

### Persistent Agent Group Roadmap

In this roadmap, a **pod** is an application pattern. It is not a proposed
public `Jido.Pod` API. Build each example with the current Agent, Plugin,
Directive, Signal, Bus, Scheduler, and Persistence contracts. If several complete
examples expose the same missing contract, use that evidence to design a new
abstraction later.

A continuously operating Agent must still perform finite turns. A Scheduler,
Heartbeat, Bus input Plugin, or external source emits a Signal. The Agent
handles the Signal, commits state, and becomes idle again. Do not put an
endless receive or work loop inside an Action. This rule keeps Agent turns
serial, observable, cancellable, and recoverable. It also lets the system work
when no chat client is connected.

Build the stack in this order. Each step must keep the contracts from all
earlier steps.

| Step | Example directory | Typical size | New system contract |
| --- | --- | ---: | --- |
| 0 | Existing examples | 1-3 Agents | Commit, child, timeout, inbox, and runtime recovery |
| 1 | `purpose_loop` | 1 Agent | Continuous purpose through finite scheduled turns |
| 2 | `fixed_group` | 3-5 Agents | Desired topology and Bus coordination |
| 3 | `elastic_group` | 5-20 Agents | Demand-based start, drain, replace, and stop |
| 4 | `persistent_campaign` | 5-25 Agents | A long-lived goal with persistent and temporary roles |
| 5 | `nested_cells` | 25-50 Agents | Hierarchical ownership and local reconciliation |
| 6 | `swarm_control` | 100+ Agents | Scale, failure isolation, and complete cleanup |
| 7 | `codebase_review_tree` | 1,500 Agents | Large ownership tree and scoped Bus traffic |
| 8 | `adaptive_swarm` | Bounded by policy | Stigmergy, recursive work, or policy evolution |

#### Step 1: One Continuous Purpose

Add `purpose_loop/`. Start with one Agent and no Bus dependency. Give it a
small deterministic purpose, such as processing one unit from a fixture-backed
queue until the queue is empty.

- [x] Store the purpose, phase, generation, budget, and last completed unit in
  Agent state.
- [x] Use `purpose.tick` to start one finite sense, decide, and act turn.
- [x] Schedule the next tick only after the current turn commits.
- [x] Coalesce or reject a duplicate tick while work for its generation is
  active.
- [x] Back off when no work exists, and wake early when new work arrives.
- [x] Support `purpose.pause`, `purpose.resume`, and `purpose.drain`.
- [x] Restart the Agent and continue from the last committed unit.
- [x] Prove that the Agent makes progress while no client sends chat messages.
- [x] Prove that no timer, job, or child process remains after stop.

This example defines what "continuous" means in Jido. It does not yet define a
group.

#### Step 2: One Fixed Group

Add `fixed_group/` after the Bus input foundation is complete. Use one Group
Controller, one Environment Agent, and two or three Worker Agents. All roles
are persistent for the life of the group.

- [x] Store desired members by stable logical ID, role, and generation.
- [x] Keep PIDs and monitors in runtime state, not persistent domain state.
- [ ] Reconcile missing desired members after a controller or worker restart.
- [ ] Make repeated start and stop requests idempotent.
- [x] Publish work on the work Bus and health or topology data on the control
  Bus.
- [x] Target or award each work item. The Bus broadcasts; it is not a work
  queue.
- [ ] Make a Worker announce `starting`, `ready`, `busy`, and `failed` state.
- [x] Stop the group and verify that all children and subscriptions stop.

The controller owns desired topology. Runtime observations are a projection of
that topology. A reconcile turn compares desired and observed state and emits
bounded start, stop, or repair Directives.

#### Step 3: One Elastic Group

Add `elastic_group/`. Keep the Controller, Environment, and Monitor roles
persistent. Start and stop temporary Workers from measured demand.

- [x] Start with a minimum worker count and a fixed maximum worker count.
- [ ] Scale up when backlog stays above a threshold for a fixed number of
  observations.
- [x] Scale down only after a cooldown and a low-demand threshold.
- [x] Use the lifecycle `starting -> ready -> busy -> draining -> stopped`.
- [ ] Stop a draining Worker only after its claim completes or its drain
  deadline expires.
- [x] Replace a Worker that stops while it owns work, and reclaim its lease.
- [x] Prevent two Workers from committing the same work result.
- [x] Keep stable logical Worker IDs across process replacement.
- [ ] Restart the Controller and reconstruct desired and observed membership.
- [x] Drive the group from 2 to 10 Workers and back to 2 without leaks.

Do not start with a complex autoscaler. Use fixed thresholds, hysteresis, and a
cooldown. This makes the expected result deterministic.

#### Step 4: One Persistent Campaign

Add `persistent_campaign/`. This is a small, local form of the control pattern
used by systems such as
[Prime Agent](https://github.com/PrimeIntellect-ai/prime-agent). It is not a
copy of that project and does not require an LLM.

Use a deterministic campaign, such as improving a rule set until it passes a
fixture suite. Keep these roles alive for the complete campaign:

- A Campaign Agent owns the goal, phase, budget, and quality gates.
- An Environment Agent or Plugin owns the fixture workspace and artifacts.
- A Memory Agent owns accepted findings and rejected attempts.
- A Monitor Agent checks progress, stalls, deadlines, and resource use.
- A Team Leader is persistent while one workstream is active.

Start temporary Explorer, Implementer, Tester, Reviewer, or Rollout Agents only
when the campaign needs them.

- [ ] Continue the campaign after the initiating client disconnects.
- [ ] Wake the Campaign Agent from schedule, result, failure, and new-evidence
  Signals.
- [ ] Start only the temporary role needed for the next bounded unit of work.
- [ ] Require a deterministic quality gate before an artifact is accepted.
- [ ] Record artifacts and evidence outside transient Worker state.
- [ ] Stop a temporary Worker after it reports a result or exhausts its budget.
- [ ] Restart the Campaign Agent and resume the active phase once.
- [ ] Detect a stalled campaign and change strategy or finish with a clear
  status.
- [ ] Finish because the goal passed, the budget ended, or cancellation won.
- [ ] Stop all temporary Agents while retaining the final campaign record.

This step is the first useful product-shaped example. It combines continuous
operation, a persistent purpose, elastic specialists, a stateful environment,
and quality-gated progress.

#### Step 5: Nested Cells

Add `nested_cells/`. A Root Controller owns several Cell Leaders. Each Cell
Leader owns a small local group. The Root Controller manages cell intent and
cell summaries. It does not manage every leaf PID.

- [ ] Use stable cell and member IDs that include a topology generation.
- [ ] Let each Cell Leader reconcile its own desired Workers.
- [ ] Report bounded cell summaries to the Root Controller.
- [ ] Route work to a cell before a local Worker claims it.
- [ ] Isolate one cell failure while other cells continue.
- [ ] Restart one Cell Leader and rebuild only its local membership.
- [ ] Drain a complete cell before removing it from desired topology.
- [ ] Prevent a nested child from becoming an unowned orphan.
- [ ] Stop the root and prove that every nested child stops.

This step keeps control traffic bounded. It also gives each group a small
failure and reconciliation domain.

#### Step 6: A 100-Agent Control Environment

Add `swarm_control/`. Use ten cells with about ten Agents per cell. Some Agents
have persistent roles. Leaf Workers remain elastic. Use a seeded synthetic
workload so each run has the same expected result.

- [ ] Ramp from the minimum topology to 25, 50, and more than 100 live Agents.
- [ ] Keep persistent Controllers, Environment, Memory, and Monitors alive
  during scale changes.
- [ ] Add and remove temporary Workers while work is active.
- [ ] Stop selected Workers and Cell Leaders and verify local recovery.
- [ ] Restart the Root Controller and preserve the active campaign generation.
- [ ] Bound starts, stops, retries, Signals, mailbox depth, and in-flight work.
- [ ] Measure backlog convergence and completion throughput without exact
  timing assertions.
- [ ] Prove that work has one terminal result despite retries and replacement.
- [ ] Drain to the minimum topology after the workload ends.
- [ ] Stop the system and verify the baseline process, subscription, and
  scheduled-job counts.

Keep a small form of this scenario in the default suite. Add a separate
`@tag :scale` form for 100 or more Agents only after the test configuration has
an explicit scale profile.

#### Step 7: A 1,500-Agent Codebase Review Tree

Add `codebase_review_tree/`. This is the large, concrete example for the stack.
It reviews a deterministic codebase fixture with one Agent for each directory
and file.

The likely historical source is commit `45c91aac` under
`examples/code_mapper/`. It used a Root Coordinator, Folder Agents, File
Agents, bounded batches, and a DETS cache. It also included an example run with
1,196 files and rules for codebases with more than 1,000 files. Reuse its
discovery, cache, tree, and aggregation ideas. Do not copy its removed Agent,
Strategy, or direct-PID contracts.

Use this exact topology for the scale profile:

```text
ReviewRoot Agent (1)
└── Directory Agents (99 across several tree levels)
    ├── Child Directory Agents
    └── FileReview Agents (1,400 total)

Total: 1,500 live Agents
```

Parent-child links own process lifecycle. Bus Signals carry review work,
results, progress, and control data.

```text
ReviewRoot
  ├── spawns top-level Directory Agents
  ├── waits for the ready barrier
  └── publishes one review.run.started Signal
                         │
                         ▼
                    Signal Bus
             ┌───────────┴───────────┐
             ▼                       ▼
      Directory Agents        FileReview Agents
       spawn children          review one file
             ▲                       │
             └── scoped result Signals
                         │
                         ▼
               summaries fold up the tree
```

Use Bus subjects or types that include `run_id` and the logical parent ID. A
Directory Agent must receive results only from its direct children. Do not
broadcast every file result to every Directory Agent.

Suggested Signals include `review.node.ready`, `review.run.started`,
`review.file.completed`, `review.directory.completed`, `review.node.failed`,
`review.run.cancelled`, and `review.run.completed`.

Build this example in four small profiles:

1. `small_tree` uses one root, four directories, and 32 files. Run it in the
   default suite.
2. `bus_tree` uses the same small fixture, but all start and result data moves
   through the Bus.
3. `scale_tree` uses exactly 1,500 live Agents and has the `:scale` tag.
4. `recovery_tree` stops selected branches and verifies scoped recovery.

##### Fixture and Review Work

Use a generated manifest instead of the current checkout. This keeps the test
stable when repository files change. The scale fixture contains 99 directory
records and 1,400 file records. Each record has a stable path, parent ID,
content hash, language, imports, public definitions, and known findings.

A deterministic File Review Action can check:

- Missing module or function documentation
- Public API size
- Import or dependency edges
- Known unsafe calls
- TODO markers
- A simple complexity score

Store complete file findings and source data in a fixture Store. Keep only
counts, hashes, status, and artifact handles in Agent state. A file result key
must include `run_id`, `file_id`, and `content_hash`.

##### Build and Start Barrier

- [ ] Let the Root Agent spawn only its direct Directory children.
- [ ] Let each Directory Agent spawn only its direct directories and files.
- [ ] Keep stable logical IDs in state and runtime PIDs in runtime state.
- [ ] Publish one `review.node.ready` Signal for each started node.
- [ ] Wait until all 1,500 Agents are live and ready before review work starts.
- [ ] Publish one `review.run.started` Signal and deliver it to all 1,499 child
  Agents.
- [ ] Prove that the start barrier does not depend on one exact process order.

The all-node start Signal is an intentional Bus broadcast. Completion Signals
must use scoped subscriptions so result traffic stays proportional to the
number of tree edges.

##### Review and Aggregation

- [ ] Make each FileReview Agent process its assigned file exactly once.
- [ ] Publish each file result to a subject scoped to its parent Directory ID.
- [ ] Let each Directory Agent accept results only from its direct children.
- [ ] Make duplicate file and directory results idempotent.
- [ ] Aggregate file results into directory summaries in stable path order.
- [ ] Publish a directory summary only after all expected direct children have
  one terminal result.
- [ ] Fold nested directory summaries into one Root report.
- [ ] Verify the expected file count, directory count, dependency edges, and
  known findings.
- [ ] Return the same report when result completion order changes.
- [ ] Keep root and directory state bounded by summary data and artifact
  handles.

##### Bus Scale and Recovery

- [ ] Use a durable subscription for each parent result stream.
- [ ] Acknowledge a child result only after its parent commits the aggregate.
- [ ] Restart one Directory Agent and redeliver its unacknowledged results.
- [ ] Stop selected FileReview Agents during work and replace them with the
  same logical IDs.
- [ ] Stop one Directory Agent and verify that its owned subtree stops.
- [ ] Rebuild only the stopped branch from desired topology and cached results.
- [ ] Ignore a late result from an older run or topology generation.
- [ ] Cancel the run with one broadcast Signal and stop the tree from leaves to
  root.
- [ ] Keep published Signals and delivered Signals proportional to the number
  of Agents and tree edges. Do not create all-to-all result delivery.

##### Completion and Cleanup

- [ ] Reach 1,500 live Agents before review starts and record the peak count.
- [ ] Complete all 1,400 file reviews within fixed Signal, retry, memory, and
  time budgets.
- [ ] Record cache hits and misses without changing the final report.
- [ ] Run a second revision and review only files with changed content hashes.
- [ ] Drain FileReview Agents before Directory Agents stop.
- [ ] Stop all Directory Agents before the Root Agent stops.
- [ ] Verify that Agent, subscription, monitor, and scheduled-job counts return
  to their baseline values.
- [ ] Verify that the final Store contains no active claims or incomplete
  directory summaries.

An optional manual runner can scan a real repository. The automated test must
use the generated fixture. The test measures Agent and Bus behavior, not local
disk speed.

#### Step 8: Adaptive Group Behavior

Only add adaptive behavior after the lifecycle and recovery contracts above
are stable. Reuse the scenarios later in this file instead of creating a new
control system for each algorithm.

- Use stigmergic marks as one input to elastic Worker placement.
- Use contract-net bids to select a temporary specialist.
- Use recursive Workers below one persistent Campaign Agent.
- Use GEPA-style evaluation to change a routing or decomposition policy.
- Promote a new policy only at a generation boundary.
- Keep policy evolution inside fixed Agent, Signal, time, and cost budgets.

#### Control and Work Planes

Keep control and work data separate, even when both use a Signal Bus.

| Control plane | Work plane |
| --- | --- |
| Desired topology and generations | Tasks, claims, results, and artifacts |
| Agent health and readiness | Capability, priority, and work deadlines |
| Scale, drain, replace, and stop decisions | Retries, leases, and idempotency keys |
| Budgets, policy versions, and campaign phase | Domain events and progress evidence |

Use a small common Signal vocabulary across the stack:
`group.reconcile.requested`, `group.member.desired`, `group.member.ready`,
`group.member.draining`, `group.member.stopped`, `group.member.failed`,
`work.offered`, `work.claimed`, `work.completed`, `work.failed`,
`purpose.tick`, `purpose.paused`, and `campaign.completed`.

These examples must test behavior, not build a general cluster scheduler. They
must stay within one Jido instance until the single-node ownership, recovery,
and cleanup rules are correct.

### Bus Input Foundation

A normal `Jido.Signal.Bus` subscription sends `{:signal, signal}` and can target
an Agent Server directly. A durable subscription sends a recorded Signal and
requires an acknowledgement. Use a small input Plugin for durable delivery.

- [x] Add a reusable Bus input Plugin that attaches subscriptions when its Agent
  starts.
- [x] Attach an ephemeral subscription again after an Agent or Plugin runtime
  restart.
- [ ] Forward one durable record to the Agent at a time.
- [ ] Acknowledge a durable record only after the Agent commits the Signal.
- [ ] Do not acknowledge a failed or cancelled Agent turn.
- [ ] Deliver an unacknowledged record again after the input Plugin restarts.
- [ ] Define an application policy for records that always fail. The Bus does
  not provide negative acknowledgement, retry timers, or a dead-letter queue.
- [ ] Remove duplicate durable delivery by Signal ID or recorded cursor.
- [ ] Restore Bus records and durable cursors after a full Bus restart with a
  custom test Store.

The Bus broadcasts each matching Signal. It is not a competing-consumer work
queue. Claims, leases, bidding, retries, dead-letter handling, and worker
selection belong to Agents in the scenario.

### Parallel Tool Calling

Use a deterministic planner in place of an LLM. It returns several tool calls
for local tools such as search fixtures, arithmetic, lookup, approval, delay,
and failure.

- [ ] Use `Jido.Flow.Map` to run pure tool Actions concurrently in one Agent
  turn.
- [ ] Verify that all tool Actions start before a blocked tool completes.
- [ ] Complete tools in a different order and return results in original call
  order.
- [ ] Commit the final conversation and Plugin state once after all tool results
  are ready.
- [ ] Test both fail-fast and collected-error policies.
- [ ] Cancel a tool wave and verify that late results cannot commit.
- [ ] Apply tool effects in stable call order when execution order differs.
- [ ] Publish tool requests through the Bus to long-lived specialist Agents.
- [ ] Gather Bus tool results by request and tool-call correlation IDs.
- [ ] Restart one tool Agent during work and complete or retry its assignment.
- [ ] Ignore duplicate, unknown, and late tool results.
- [ ] Bound parallel work and verify that excess tool calls wait.

The local Flow form tests execution concurrency inside one Agent turn. The Bus
form tests coordination across independent Agent turns.

### Contract-Net Task Market

A coordinator publishes `task.offered`. Worker Agents publish `task.bid` with
capability, load, expected time, cost, and reliability. The coordinator
publishes an award to one worker, and the winner publishes `task.completed`.

- [ ] Select the best valid bid with a stable tie-break rule.
- [ ] Reject bids that arrive after the award deadline.
- [ ] Verify that only the awarded worker performs the task.
- [ ] Award the task again when the selected worker stops before completion.
- [ ] Make bids, awards, and results idempotent.
- [ ] Track worker reliability and use it in later awards.
- [ ] Prevent starvation across many tasks and workers.
- [ ] Recover the active auction from durable Bus records.
- [ ] Close all auctions when the coordinator stops or reaches its work budget.

### Stigmergic Route-Finding Swarm

Create a fixed graph or grid. Ant Agents do not send direct messages to each
other. They publish observations and marks. An Environment Agent owns the
authoritative pheromone map and publishes world revisions. Use deterministic
choices or fixed random seeds.

- [ ] Let several ant Agents explore different paths at the same time.
- [ ] Deposit stronger marks on successful and shorter paths.
- [ ] Make later ants prefer stronger paths without direct Agent coordination.
- [ ] Evaporate marks with the Scheduler Plugin.
- [ ] Change the graph and verify that evaporation permits a new path to win.
- [ ] Ignore duplicate mark deposits from at-least-once delivery.
- [ ] Restart an ant and continue from the current world revision.
- [ ] Rebuild the Environment Agent from durable Bus replay.
- [ ] Add hop, generation, and Signal budgets to prevent an endless feedback
  loop.
- [ ] Verify convergence on the expected path within a fixed number of rounds.
- [ ] Verify that no ant stores another ant PID or reads another ant state.

### Shared Blackboard Deliberation

A Blackboard Agent owns versioned proposals and evidence. Proposer, critic,
verifier, cost, and arbiter Agents subscribe to Blackboard changes and publish
their own contributions.

- [ ] Run all specialists for one revision at the same time.
- [ ] Reject or rebase contributions made against an old revision.
- [ ] Keep conflicting proposals separate until the arbiter resolves them.
- [ ] Approve a proposal after a defined quorum.
- [ ] Finish at a deadline with partial evidence and a clear status.
- [ ] Rebuild the complete decision record from durable replay.
- [ ] Restart a specialist and join at the current Blackboard revision.
- [ ] Prevent a critic-to-proposer feedback loop from exceeding its round
  budget.

### Distributed Graph Search

A root Agent publishes frontier nodes. Explorer Agents claim nodes, inspect
local fixtures, and publish discoveries.

- [ ] Process several frontier nodes at the same time.
- [ ] Process each graph node once despite duplicate discoveries.
- [ ] Merge the same node discovered through different paths.
- [ ] Release or expire a claim when an explorer stops.
- [ ] Cancel unused work after a goal is found.
- [ ] Resume the search from durable Bus state.
- [ ] Bound search depth, node count, and Agent count.
- [ ] Return a stable path when discoveries complete in different orders.

### Warehouse Robot Swarm

Robot Agents move through a grid. A World Agent owns cell reservations and
congestion marks.

- [ ] Prevent two robots from reserving the same cell.
- [ ] Find alternate routes around active reservations and congestion.
- [ ] Release reservations after a robot stops.
- [ ] Detect and break a reservation deadlock.
- [ ] Decay congestion marks with scheduled Signals.
- [ ] Complete all deliveries without collision or starvation.
- [ ] Recover world reservations after the World Agent restarts.

### Incident-Response Swarm

Detector Agents publish evidence. A Correlator Agent opens an incident after a
threshold. Responder Agents bid for response work. A Memory Agent records a
rule after resolution.

- [ ] Require independent evidence from a defined number of detectors.
- [ ] Prevent duplicate evidence from satisfying the threshold.
- [ ] Update a closed incident with late evidence without reopening it.
- [ ] Let one responder claim each remediation action.
- [ ] Escalate after failed or timed-out remediation.
- [ ] Publish and apply a new deterministic detection rule after resolution.
- [ ] Recover open incidents and responder claims after a restart.

### Adaptive Service Router

Service Agents process the same type of work. A Router Agent tracks success,
latency, load, and failures from result Signals.

- [ ] Distribute initial work evenly.
- [ ] Send less work to a slow or failing service.
- [ ] Decay scores so a recovered service can receive work again.
- [ ] Prevent a burst from sending all work to one service.
- [ ] Keep durable reputation after the Router Agent restarts.
- [ ] Reject stale results from an older routing decision.
- [ ] Preserve a minimum traffic share for health checks and recovery.

### Bus Isolation and Federation

- [ ] Keep Buses with the same name isolated between Jido instances or tenants.
- [ ] Use separate Buses so one slow durable workload does not delay unrelated
  publication.
- [ ] Forward selected Signals between two Buses through a bridge Agent.
- [ ] Preserve trace and causation data across the bridge.
- [ ] Add bridge identity and hop limits to prevent a Signal loop.
- [ ] Stop one tenant Bus and verify that other tenant Agents continue.

## Recursive and Adaptive Agent Systems

### GEPA-Style Reflective Evolution

[GEPA](https://arxiv.org/abs/2507.19457) is a Genetic-Pareto optimizer. It
evaluates system trajectories, turns diagnostic feedback into candidate
changes, and keeps candidates with complementary strengths on a Pareto
frontier. A local simulation can evolve a human-readable tool-routing or
incident-response rule set without an LLM.

Suggested Agents:

- A Population Agent owns candidate IDs, lineage, and generation state.
- Rollout Agents evaluate candidates against deterministic fixtures in
  parallel.
- An Evaluator Agent produces scores and structured diagnostic feedback.
- A Reflector Agent converts known failure types into deterministic mutations.
- A Frontier Agent keeps candidates that are best for different cases or
  metrics.
- A Merger Agent combines compatible rules from complementary candidates.

Suggested Signals include `gepa.candidate.proposed`,
`gepa.rollout.requested`, `gepa.rollout.completed`,
`gepa.feedback.generated`, `gepa.mutation.proposed`,
`gepa.frontier.updated`, and `gepa.generation.completed`.

- [ ] Evaluate one candidate on several fixtures at the same time.
- [ ] Keep rollout results stable when completion order changes.
- [ ] Enforce generation, rollout, Agent, and time budgets.
- [ ] Create a mutation from a known failure and improve its target fixture.
- [ ] Keep complementary candidates instead of selecting only one scalar-score
  winner.
- [ ] Merge compatible rules and preserve both parent IDs in lineage.
- [ ] Reject duplicate candidates by a stable semantic hash.
- [ ] Keep held-out evaluation cases out of mutation feedback.
- [ ] Restart the Population Agent and resume the active generation.
- [ ] Stop orphan rollout Agents when a generation is cancelled.
- [ ] Converge on a known optimal rule set for a small deterministic benchmark.
- [ ] Verify that every accepted candidate can be explained by its parent,
  feedback, mutation, and rollout records.

### Recursive Language Model Simulation

The [LLM example](../../docs/examples/profiles/03_llm/03_10_recursive_analysis.md)
implements bounded recursive calls inside one Turn, with a local corpus store
and scripted model. Its stress runner can run several root Agents at once.
The child Agent lifecycle and recovery requirements below remain future work.

[Recursive Language Models](https://arxiv.org/abs/2512.24601) treat a large
prompt as an external environment. A root model examines selected ranges,
programmatically creates recursive calls over transformed ranges, stores
intermediate values outside its context, and returns a final value. A local
Agent simulation can use a large fixture corpus and deterministic classifier,
search, and reducer Actions.

Suggested Agents:

- A Corpus Agent or Store owns the large input and intermediate variables.
- A Root Agent owns task metadata, handles, budgets, and final status.
- Recursive Worker Agents use the same Agent module at different depths.
- A Reducer Agent joins child results and returns them to the parent call.
- A Budget Agent or root-owned policy limits depth, calls, bytes, and time.

Suggested Signals include `rlm.call.requested`, `rlm.context.read`,
`rlm.call.started`, `rlm.partial.completed`, `rlm.call.completed`,
`rlm.call.failed`, and `rlm.call.cancelled`.

- [ ] Keep the large corpus outside Root and Worker Agent state.
- [ ] Give each recursive call only a handle, range, query, depth, and budget.
- [ ] Split a range, start child calls, and join results through parent call IDs.
- [ ] Run independent recursive calls at the same time.
- [ ] Return stable results when child completion order changes.
- [ ] Enforce maximum depth, total calls, bytes read, Agent count, and wall time.
- [ ] Cancel all descendants when the root call is cancelled or completed.
- [ ] Retry or replace a child that stops before it publishes a result.
- [ ] Ignore duplicate and late child results.
- [ ] Persist the recursion tree and resume incomplete work after a root restart.
- [ ] Record which corpus ranges each call reads and prove that it does not read
  the complete corpus by default.
- [ ] Test constant-work search with one hidden fact in a large corpus.
- [ ] Test linear-work classification and aggregation across every chunk.
- [ ] Test pairwise work that compares selected results from different chunks.
- [ ] Use adaptive recursion: split only ranges that the deterministic evaluator
  marks as uncertain.
- [ ] Verify that the final result can be larger than one child result while no
  child holds the complete result during processing.

### GEPA-Guided Recursive Policy Evolution

Combine both simulations. GEPA candidates define an RLM decomposition policy,
such as chunk size, maximum depth, search order, merge rule, and parallelism.
The deterministic RLM benchmark supplies accuracy, bytes-read, call-count, and
latency scores.

- [ ] Evaluate several recursive policies in parallel on the same corpus.
- [ ] Keep a Pareto frontier for accuracy, work, depth, and latency.
- [ ] Mutate one policy after a trace shows excess reads or a missed result.
- [ ] Merge complementary search and aggregation policies.
- [ ] Prevent evaluation Agents from changing the active production policy.
- [ ] Promote one policy only after it passes held-out corpus cases.
- [ ] Reproduce the promoted policy from its candidate lineage and Bus records.

## Large-System Test Rules

- Assert safety properties for every intermediate state and convergence
  properties for the final state.
- Do not assert one exact interleaving when several valid interleavings exist.
- Give every recursive, swarm, feedback, and retry loop a fixed budget.
- Use stable Signal IDs, correlation IDs, generation IDs, and world revisions.
- Make all at-least-once delivery handlers idempotent.
- Keep authoritative shared state in an Agent or external Store, not in test
  process state.
- Do not use the Bus replay log as a general query database.
- Do not treat the local Bus as distributed consensus.
- Use separate Buses when workload isolation is part of the scenario.
