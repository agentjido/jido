# Aspirational example table of contents

Status: Draft for discussion

This document proposes a new learning structure for the Jido examples. It is
not the machine-readable example catalog. Chapter numbers and lesson IDs are
not stable until the structure is approved.

The outline follows the Jido learning path:

1. Action
2. Flow
3. Agent
4. Plugin
5. AgentServer
6. Jido instance and Catalog

AI is a first-party capability on this foundation. It is not the foundation
of the first Jido lesson.

## Suite model

The examples have two equal purposes:

- Teach the Jido API in a progressive order.
- Test the integration contracts that the examples describe.

Do not divide examples into Learn and Prove tracks. Put normal behavior,
validation, failure, recovery, and compatibility in the same learning
sequence. Each example must teach its public contract and test that contract.

The complete suite runs without network access, credentials, or paid APIs.
Use deterministic local adapters to preserve each application boundary. Do
not add live-provider, external-service, or paid runners to this suite.

## Dogfooding and core-gap feedback

The examples are executable design probes for Jido core. Implement each
application capability end to end with current public Actions, Flows, Agents,
Signals, Sessions, and runtime contracts before a new core abstraction is
proposed.

Do not hide an awkward boundary with a private API or test-only helper. A local
fixture can replace an external service, but it must keep the same Jido Flow and
application boundary. Each advanced example must record evidence of:

- Public contracts that compose cleanly.
- Repeated glue or application code that might need a reusable helper.
- Missing public operations or unclear ownership.
- Persistence, portability, concurrency, recovery, or replay gaps.
- Weak error, telemetry, security, or testing contracts.
- Performance limits or control points that the application cannot express.

Classify each finding as application code, an ecosystem package concern, a
documentation gap, or a candidate Jido core change. The example does not need
to solve every gap. It must make the gap concrete and reproducible.

## Jido strengths to prove

Use these ideas as recurring, tested through-lines. Do not use them only as
marketing claims:

- The same Agent command uses the `Agent.cmd/3` evaluation boundary or
  AgentServer hosting.
- The logical Agent identity survives the process that currently hosts it.
- Processes are disposable. Agent state can be durable.
- AgentServer commits valid state before it runs AgentServer-managed effects.
- One Action uses the same execution model as one Flow.
- Code-defined and data-defined Agents use the same portable contracts where
  their registered targets are equivalent.
- A Plugin can own one complete vertical capability.
- Topology describes ownership and delivery. It does not create shared memory.
- A saved parent does not imply one coordinated checkpoint of all child state.
- Recovery behavior is explicit, observable, and tested.
- Scale and Agent-density claims require reproducible measurements.

## Cross-cutting contracts

Values and validation do not need a separate chapter. Teach each contract at
the first boundary where a developer needs it:

- Teach `Jido.Joi` and `Jido.Error` with Action input and output boundaries.
- Teach `Jido.Expr` with Flow conditions.
- Teach `Jido.Instruction` when one Action becomes a one-step Flow, and again
  with Invoke and Handoff.
- Teach `Jido.Id` when Agent, Signal, and Turn identities first appear.
- Teach portable values with stored Flow and Agent documents.
- Teach `Jido.Codec.Term` limits with persistence and external documents.

Each lesson must explain the validation errors that its public boundary can
return. A reference page can index these contracts after the learning path is
stable.

## Part I: Learn the Jido model

### 00 Start Here

Purpose: Complete the first-hour Jido path with one coherent, non-AI example.

Proposed lessons:

1. Define validated Agent state.
2. Define and test one Action.
3. Compose and test one Flow without a process.
4. Route one Signal to the Flow.
5. Start the Agent under AgentServer.
6. Inspect state, Turn status, waits, effects, and the last failure.

The six lessons must extend one example application. A developer should not need
to learn Spark, Runic, `:gen_statem`, generated modules, or AgentServer
callbacks.

### 01 Actions

Purpose: Teach one validated unit of work before workflow composition.

Proposed lessons:

1. Action input and output schemas with Joi.
2. Action context.
3. Structured errors, error paths, and output validation.
4. Effects as data.
5. Inline Actions.
6. Testing Actions.

Primary coverage:

- `Jido.Action`
- `Jido.Action.Inline`
- `Jido.Action.Output`
- `Jido.Action.Validation`
- `Jido.Joi`
- `Jido.Error`

### 02 Flow Authoring

Purpose: Build and inspect deterministic behavior graphs.

Proposed lessons:

1. Steps and references.
2. Data and control dependencies.
3. Inputs and explicit output.
4. Expressions and safe conditions.
5. DSL, Map, and JSON authoring equivalence.
6. Invalid references and cycles.
7. Flow identity and versioning.
8. Stored Flow documents.
9. Flow inspection.

Primary coverage:

- `Jido.Flow`
- `Jido.Flow.Ref`
- `Jido.Flow.Graph`
- `Jido.Flow.Validation`
- `Jido.Flow.Codec`
- `Jido.Expr`

### 03 Flow Execution

Purpose: Run authored Flows with one execution model.

Proposed lessons:

1. Run one Action as its canonical one-step Flow.
2. Sequential work.
3. Choice and fallback.
4. Parallel work and ordered joins.
5. Map and Reduce.
6. Bounded Iterate.
7. Nested Flows.
8. Invoke and Handoff.
9. Wait and resume.
10. Effects and failures.
11. Runic compilation as an advanced escape path.

The first lesson must show that Jido lowers one Action into a canonical
one-step Flow. Actions and authored Flows use the same compile and execution
path. The lesson must not present Action execution as a second runtime model.
All Flow patterns stay in this chapter.

Primary coverage:

- `Jido.Exec`
- `Jido.Exec.Result`
- `Jido.Exec.Wait`
- `Jido.Instruction`
- Flow component execution
- Runic compilation and execution

### 04 Agents

Purpose: Add identity, state, routes, and pure Turns to Flow behavior.

Proposed lessons:

1. Agent definition, instance, identity, and stable Address.
2. State schemas and defaults.
3. Exact routes, wildcard routes, and precedence.
4. Pure execution with `Agent.cmd/3`.
5. Replies and Directives.
6. Agent callbacks.
7. Safe framework-neutral Agent views.
8. Code-defined and data-defined Agent parity.
9. Definition upgrades.

The parity lesson must send equivalent input through code-defined and
data-defined Agents. It must compare validation, route selection, state, reply,
and Directive results. The parity claim applies only when both definitions use
equivalent registered targets. A callback that exists only as Elixir code is
outside the data-defined parity claim.

Primary coverage:

- `Jido.Agent`
- `Jido.Agent.Route`
- `Jido.Agent.Address`
- `Jido.Agent.View`
- `Jido.Agent.Codec`
- `Jido.Id`

`Jido.Agent.View.project/3` gives a JSON-safe view of one Agent definition and
its public operations. It does not contact an Agent process or include Agent
state, metadata, Plugin options, private defaults, or module names. It can
describe an Agent to a UI, but it is not a Phoenix View or a runtime state API.

### 05 Plugins

Purpose: Add one reusable vertical capability with explicit ownership.

Proposed lessons:

1. Plugin-owned state.
2. Prepared input.
3. Runtime admission.
4. State reduction and post-commit hooks.
5. Custom Directives.
6. Supervised runtime resources.
7. Plugin DSL extensions.
8. Plugin persistence.
9. Plugin order and composition.

The headline Plugin example is **Complete Plugin Vertical Ownership**. One
Plugin owns its state, input preparation, admission rules, state reduction,
Directives, supervised runtime children, persistence conversion, and
post-commit hooks. Its documentation and tests show the startup, commit,
effect, and cleanup order. The capability must not be split between hidden
Agent callbacks and test support.

Primary coverage:

- `Jido.Plugin`
- Plugin preparation and admission
- Plugin reduction and commit contexts
- Plugin runtime children
- Plugin persistence facets

## Part II: Run Jido systems

### 06 AgentServer

Purpose: Run an Agent as a supervised actor with one Turn lifecycle.

Proposed lessons:

1. Start and address an Agent.
2. Pure and Hosted Execution Parity.
3. Call, cast, submit, and await.
4. TurnResult and the commit boundary.
5. Commit Before Effects.
6. Admission, cancellation, quiesce, and resume.
7. Waits and managed jobs.
8. Status and snapshots.
9. Hibernation and thaw.
10. Runtime upgrades and failures.

**Pure and Hosted Execution Parity** sends the same Signal to the same Agent
behavior through `Agent.cmd/3` and AgentServer. It compares the pure candidate
state with the hosted committed state. It also verifies that hosted execution
performs the Directives that pure execution returns. AgentServer owns the
process lifecycle, commit, and effect execution. The example must not claim
that pure execution has a hosted lifecycle. The pure claim applies to the Jido
evaluation boundary. An Action can still run application code that has its own
side effects.

**Commit Before Effects** injects an effect failure after AgentServer commits
valid state. The test proves that the state and revision stay committed and
that the effect failure is visible. It must not roll back the committed state
or claim exactly-once effect delivery. If the application needs compensation,
the example must model it as explicit later work. The commit-order guarantee
applies to AgentServer-managed effects. It cannot reorder a side effect that an
Action performs inside its own execution.

Primary coverage:

- `Jido.AgentServer`
- `Jido.AgentServer.TurnResult`
- `Jido.AgentServer.Status`
- `Jido.AgentServer.Snapshot`
- Agent activation lifecycle

### 07 Jido Instance, Catalog, and Documents

Purpose: Explain the application-level runtime and definition boundary.

Proposed lessons:

1. Start and configure a Jido instance.
2. Namespaces and partitions.
3. Stable Agent Addresses.
4. Logical Agent identity and current process identity.
5. Catalog discovery and package contributions.
6. Portable values and forbidden runtime values.
7. Codec documents, stable references, and term limits.
8. Installed definitions and application supervision.

A stable Agent Address identifies the logical Agent. A PID identifies only
the process for the current activation. For a durable Agent, the logical
identity can remain after that process stops and can resolve to a later
activation. An Agent Address is not an authorization
credential.

Primary coverage:

- `Jido.Instance`
- `Jido.Catalog`
- `Jido.Catalog.Discovery`
- `Jido.Codec`
- `Jido.Codec.Term`
- `Jido.Application`

### 08 Signals and Messaging

Purpose: Give Signal construction, routing, and delivery one complete path.

Proposed lessons:

1. CloudEvents envelope and custom Signal types.
2. Signal schemas and context.
3. Router DSL and route precedence.
4. PID, PubSub, HTTP, Logger, and custom dispatch.
5. Signal Bus publication and replay.
6. Durable subscriptions, acknowledgement, and retry.
7. Trace and causation propagation.
8. Follow One Signal.
9. Delivery guarantees and limits.

**Follow One Signal** traces one request from a stable Agent target through
routing, a Turn, correlated child work, and the final reply. The example shows
the Signal ID, request and Turn IDs, correlation, causation, trace context,
child activation, and reply address at each boundary. Tests must inject one
delivery failure and state the retry and duplicate-delivery limits. The child
uses the ownership rules from the next chapter.

Primary coverage:

- `Jido.Signal`
- `Jido.Signal.Router`
- `Jido.Signal.Dispatch`
- `Jido.Signal.Bus`
- `Jido.Trace`

### 09 Dynamic Agent Composition

Purpose: Explain runtime Agent creation, ownership, correlation, and transfer.

Proposed lessons:

1. Owned child Agents.
2. Child start, restart, and stop.
3. Correlated requests and replies.
4. Independent Agents.
5. Orphan adoption and ownership transfer.
6. Shutdown and ownership limits.

This chapter covers composition decisions made during execution. It does not
cover members that belong to a saved Agent definition.

The examples must name the logical owner and the process owner of every child.
They must show child process loss, restart, adoption of an independent Agent,
ownership transfer, and owner shutdown. Tests must prove which children stop,
which Agents remain available, and which request correlations survive. The
examples must not imply remote failover or shared mutable state.

### 10 Declared Agent Topologies

Purpose: Explain members and connections that belong to a saved Agent
definition.

Proposed lessons:

1. Named topology members.
2. Member identity and counted members.
3. Direct connections.
4. Bus broadcast.
5. Nested topology.
6. Definition and JSON parity.
7. Snapshot, member-state, and delivery limits.
8. Failure isolation between teams.
9. Shutdown and subtree removal.

This chapter covers topology intent as definition data. It must state that a
parent snapshot does not make one coordinated checkpoint of all member state.
The main topology example has nested, organization-shaped teams. It injects a
member failure, proves failure isolation, removes one subtree, and verifies
cleanup. Topology describes ownership and delivery. It does not create shared
memory. Saved parent intent does not mean that all child state has one atomic
checkpoint.

### 11 Built-in Capabilities

Purpose: Show the capabilities that Jido includes.

Proposed lessons:

1. Audit records.
2. One-shot scheduling.
3. Recurring schedules and cron.
4. Heartbeats.
5. SensorManager.
6. Bus Manager and Bus Client.

Primary coverage:

- `Jido.Plugin.Audit`
- `Jido.Plugin.Scheduler`
- `Jido.Plugin.Heartbeat`
- `Jido.Plugin.SensorManager`
- `Jido.Plugin.Bus.Manager`
- `Jido.Plugin.Bus.Client`

### 12 Persistence

Purpose: Store and restore Agent state safely.

Proposed lessons:

1. Persistent Agent records.
2. Checkpoints and revisions.
3. Local persistence adapters.
4. Hibernate and thaw.
5. Compare-and-swap conflicts and uncertain writes.
6. Tombstones and durable deletion.
7. Plugin state conversion.
8. Definition revision, state migration, and rollback evidence.

An upgrade example must record the definition revision and the state revision.
A failed migration must not publish partial state. A rollback claim is valid
only when the example restores a compatible definition and state revision and
then proves that the Agent can run again.

Primary coverage:

- `Jido.Persistence`
- `Jido.Persistence.Checkpoint`
- `Jido.Persistence.Store`
- ETS, File, and Mnesia adapters
- Plugin persistence

### 13 Durable Flow and Agent Execution

Purpose: Present `Jido.Durable` and durable AgentServer hosting as one learning
path.

Proposed lessons:

1. Choose between `Jido.Durable` and durable AgentServer hosting.
2. Durable Flow start and result.
3. Saved Flow progress and completion.
4. Durable Approval Agent.
5. Durable Agent activation.
6. Passive Agent Fleet.
7. Process recovery drill.
8. BEAM recovery drill.
9. External uncertainty and idempotency.
10. Durable topology and current limits.

The chapter has two named API sections and one shared recovery section:

- Durable Flows through the `Jido.Durable` facade.
- Durable Agent activation through AgentServer.
- Recovery, idempotency, scale, and topology limits across both modes.

The first lesson must explain the difference between the two runtime modes.
The examples must then show how both modes use the same Flow, wait, persistence,
and recovery contracts.

**Durable Approval Agent** starts work, stores a wait, and loses its hosting
process. A later Signal activates the same logical Agent. The example sends the
same approval twice and proves that the Agent completes once. It records the
approval idempotency key, persisted wait and progress data, commit point, and
duplicate handling. The test must distinguish process recovery from BEAM
recovery.

**Passive Agent Fleet** creates many logical Agents but keeps only active work
in processes. It measures logical Agent count, resident process count,
activation and passivation throughput, latency percentiles, memory use, and
store load. The benchmark must publish its environment and inputs. An Agent
density claim is not valid without reproducible measurements.

The process and BEAM recovery drills inject failures at named boundaries. Each
drill shows what was committed, what is read during activation, which work can
repeat, and the final recovery result. Processes are disposable. Durable Agent
state must not depend on one process remaining alive.

### 14 Observability

Purpose: Explain Jido operation through public semantic data.

Proposed lessons:

1. Semantic telemetry events.
2. Metrics.
3. Trace context and causation.
4. OpenTelemetry integration.
5. Runtime status and telemetry timelines.
6. Debugging failed Turns.
7. Redaction and safe metadata.
8. Activation, passivation, and recovery measurements.

The observability examples must connect logical Agent identity to each process
activation. Fleet reports must separate logical Agent count from resident
process count. Recovery timelines must show the commit, failure, retry, and
result boundaries.

Primary coverage:

- `Jido.Telemetry`
- `Jido.Trace`
- AgentServer semantic events
- Exec and persistence events
- OpenTelemetry adapters

## Part III: Add AI

The application-level AI chapters use normal Jido Actions, Flows, Agents,
Sessions, persistence, waits, and telemetry. Memory, retrieval, guardrails,
middleware, and evaluation are pattern names in this outline. The examples do
not assume new Jido core APIs. They intentionally use the existing Flow model
to expose places where a later core change could be justified.

### 15 AI Agents

Purpose: Add model-backed behavior to the normal Agent model.

Proposed lessons:

1. Basic AI Agent.
2. Model configuration.
3. Model capabilities and application preflight checks.
4. Multimodal input with text and media content parts.
5. Application Actions for image, audio, video, OCR, and speech operations.
6. Action and Flow tools.
7. Structured output.
8. Limits, budgets, and usage.
9. Streaming.
10. Tool policy and human review.
11. Skills and toolsets.
12. Tool sources and the offline MCP boundary.
13. JSON AI Agents.
14. Offline testing.

Primary coverage:

- `Jido.AI.Agent`
- `Jido.AI.InferenceClient`
- `Jido.AI.ToolSource`
- AI tools and tool results
- Request policy
- Usage and budgets

Built-in reasoning uses `generate_text/3` and `stream_text/3`. A text request
can contain supported media content parts. Other multimodal operations use the
matching `Jido.AI.InferenceClient` callback from an application Action or Flow.
The examples must not imply that Jido core supplies built-in image, audio, or
video workflows. Offline clients test content shape and Flow behavior. The
suite does not call real media providers.

Official MCP client support comes from `jido_connect` through
`Jido.AI.ToolSource`. The offline example uses a deterministic ToolSource
fixture. It does not start an MCP server or implement an MCP client. Jido core
owns the ToolSource contract. It does not own the MCP client implementation.

### 16 Guardrail Flows

Purpose: Put explicit policy checks around model and tool boundaries with
normal Jido Flows.

Proposed lessons:

1. Input checks before inference.
2. Output checks before use or dispatch.
3. Tool-call checks before execution.
4. Tool-result checks before model reuse.
5. PII detection, prompt-injection checks, and moderation.
6. Human review with Wait and resume.
7. Fail-open and fail-closed Flow branches.
8. Audit records, telemetry, and trace context.

Guardrails are explicit Actions and Flow branches. They are not implicit
middleware. Each example must state which boundary it protects, what happens
when a check fails, and which evidence enters the audit record.

### 17 AI Reasoning Flows

Purpose: Show that reasoning strategies are normal Flow recipes.

Proposed comparison lessons:

1. ReAct and tool-use loops.
2. Chain of Thought, Chain of Draft, and Algorithm of Thoughts.
3. Tree of Thoughts and Graph of Thoughts.
4. TRM and Adaptive reasoning.
5. Custom reasoning Flows, strategy selection, and trade-offs.

Primary coverage:

- `Jido.AI.Reasoning.ReAct`
- `Jido.AI.Reasoning.ChainOfThought`
- `Jido.AI.Reasoning.ChainOfDraft`
- `Jido.AI.Reasoning.TreeOfThoughts`
- `Jido.AI.Reasoning.GraphOfThoughts`
- `Jido.AI.Reasoning.AlgorithmOfThoughts`
- `Jido.AI.Reasoning.TRM`
- `Jido.AI.Reasoning.Adaptive`

### 18 Model Resilience

Purpose: Make model and provider failure behavior explicit and bounded.

Proposed lessons:

1. Retryable and non-retryable model errors.
2. Retry count, elapsed-time, token, and cost budgets.
3. Ordered fallback models and capability compatibility.
4. Structured-output repair compared with a model retry.
5. Partial streaming failure and final Session commit behavior.
6. Tool errors as safe model input.
7. Provider and model attempt telemetry.
8. Scripted outages, rate limits, timeouts, and malformed output.
9. Offline provider resilience matrix.

ReAct owns the built-in retry, fallback-model, and output-repair path. Other
reasoning strategies do not retry a failed model call or select a fallback
model. The examples must not imply that all strategies have ReAct resilience.

A fallback model can change cost, latency, capabilities, and output behavior.
Each result must record the selected model and usage. Jido core does not add a
hidden circuit breaker, hedged request, or cross-request provider router.
Invalid credentials and configuration errors are not retryable. A fallback
provider must have its own valid credentials and must not hide an authorization
failure.

### 19 Sessions and Conversations

Purpose: Keep Session and Thread contracts separate from provider mechanics.

Proposed lessons:

1. Thread values.
2. Session values.
3. AI conversation projection.
4. Conversation history and public UI projection.
5. Failed and incomplete exchanges.
6. Concurrent request modes.
7. Persistence and restoration.
8. Non-AI Session use.

Primary coverage:

- `Jido.Thread`
- `Jido.Thread.Entry`
- `Jido.Session`
- AI Thread projection

### 20 Context and Memory Flows

Purpose: Assemble model context and manage application-owned memory with normal
Jido Flows.

Proposed lessons:

1. Static instructions, request input, and dynamic context layers.
2. Open, prepared, and completed model-context stages.
3. Idempotent context transforms and prompt assembly.
4. Context projection from Agent, Session, and resource data.
5. Message, byte, token, time, and cost budgets.
6. Deterministic history trimming.
7. Model-assisted history compaction through an application Action.
8. Structured working memory in application-owned state.
9. Semantic recall through an application-supplied Action.
10. Agent, Session, resource, and tenant scope.
11. Provider prompt caching and cache observations.
12. Long-running Session rollover and archival.
13. Persistence and concurrent update behavior.
14. Provenance, replay, and compaction limits.

These examples must make ownership and scope explicit. A context window limits
what one model call sees. It does not delete the full Session history. Prompt
caching is provider-dependent and does not compact the Session.

Model compaction is lossy and runs as an application Flow. For a long-running
conversation, the application can close one Session, create a new Session, and
carry forward a compacted summary with explicit lineage. Jido core does not
perform automatic compaction or Session rollover.

Semantic recall depends on an application or external storage Action. Replay
is only valid when the example records the context inputs, scope, retrieval
results, model configuration, prompt version, and compaction output that
affected the request.

### 21 Knowledge and RAG Flows

Purpose: Build retrieval-augmented generation as normal Actions and Flows.

Proposed lessons:

1. Deterministic two-step retrieval and generation.
2. Agentic RAG through an Action or Flow tool.
3. Durable document ingestion and refresh.
4. Document loading and chunking.
5. Embedding and storage.
6. Retrieval and reranking.
7. Citation assembly and provenance.
8. Retrieval and answer quality gates.

The default examples use offline documents, embeddings, retrieval fixtures,
and scorers. Deterministic local adapters replace vector stores, embedding
services, rerankers, and model providers. The application supplies storage and
retrieval Actions. Jido core does not own a Retriever API.

### 22 Application-Level Evaluation Examples

Purpose: Test AI application behavior without adding an evaluation runtime to
Jido core.

Proposed lessons:

1. Datasets and named cases as test fixtures.
2. Deterministic scorers and assertions.
3. Offline model judges with recorded inputs and outputs.
4. Tool trajectory and argument checks.
5. Budget, latency, and token checks.
6. Failure, refusal, and guardrail cases.
7. Offline regression fixtures and repeatable experiments.

Evaluation uses normal example runners, ExUnit tests, Flow results, tool traces,
usage data, and telemetry. Every scorer must state what it measures and what it
does not prove. The suite does not include live experiments.

## Part IV: Build complete agent systems

### 23 Collaborative Agent Systems

Purpose: Show how a group of specialized Agents completes one shared mission.

Proposed examples:

1. Incident-Response Organization.
2. A specialist pipeline with sequential handoff.
3. A manager and worker pool with correlated delegation.
4. A research-and-publishing team with parallel work and review.
5. A service-operations team with intake, assignment, quality review, and
   human approval.
6. A nested organization with team and department boundaries.

The examples together cover:

- Roles, goals, tasks, and explicit result contracts.
- Parallel work with one reducer.
- A bounded critic and revision loop.
- Shared artifacts with one explicit state owner.
- Human approval, escalation, and cancellation.
- Team budgets, status, traces, and failure isolation.
- Durable mission recovery after process or BEAM failure.

**Incident-Response Organization** is the main non-chat multi-Agent showcase.
A sensor reports an incident. A coordinator owns the canonical incident state
and activates nested triage and specialist teams. The organization correlates
child work, escalates to a human, isolates one failed team, removes a finished
subtree, and recovers after coordinator process loss. The default runner is
deterministic and can use a local inference fixture for model-backed analysis.

This example must name the state owner for each artifact and decision. Team
topology describes ownership and delivery. It does not create shared memory.
A saved coordinator does not imply one coordinated checkpoint of every member.
The recovery tests must state which member work can repeat and which state is
durable.

The research-and-publishing team is the CrewAI-style example:

- A coordinator plans the mission and owns its canonical state.
- Research Agents gather evidence in parallel.
- An analyst reduces evidence into findings.
- A writer produces a draft.
- A critic checks the draft and can request a bounded revision.
- A human approves publication or returns the draft for more work.

This is the Jido form of a CrewAI-style team. It uses normal Agent definitions,
Flows, topology, Signals, correlated requests, Sessions, budgets, and durable
state. It must not create a second orchestration API based on roles or tasks.
The runner uses deterministic inference fixtures. It does not use a live model
provider.

The first version must not claim shared mutable team memory or transparent
recovery of all member state. The coordinator owns canonical mission state.
Each specialist is disposable or uses its own persistence contract. Tests must
show partial failure, bounded retries, and coordinator recovery.

### 24 Application Patterns

Purpose: Combine known contracts into complete local applications.

Proposed lessons:

1. Approval workflow.
2. Inbox.
3. Runtime subscription.
4. Purpose loop.
5. Compensation.
6. Phoenix Playground LiveView chat.
7. Recoverable external delivery.
8. Controlled Agent Upgrade.

These lessons must not introduce new core API concepts. They should show how
the earlier contracts work together.

**Recoverable External Delivery** commits an outbound delivery intent before
it runs the external effect. It uses one idempotency key for the first attempt
and all retries. The failure drill lets the remote service accept the request,
then loses the acknowledgement. Recovery retries with the same key, records
the acknowledgement, and completes. A terminal failure takes an explicit
compensation path. The example must not claim exactly-once delivery. It must
state how it handles an uncertain remote outcome.

**Controlled Agent Upgrade** quiesces the Agent, settles or cancels accepted
work, records the definition and state revisions, changes the definition,
migrates state, and resumes the Agent. The failure drill injects a migration or
startup failure. It then restores the old compatible definition and state and
proves that the Agent can resume. The example must not claim safe rollback if
the public contracts cannot prove each step. It must record any missing
contract as a core gap.

The Phoenix example is an end-to-end chat application in one Phoenix Playground
script. It runs offline and stays outside Jido core. The example must:

- Start Phoenix LiveView and one Jido instance from the script.
- Create or resolve one Session-backed AI Agent for a conversation ID.
- Keep a stable `Jido.Agent.Address` instead of a process identifier in LiveView
  socket assigns.
- Send user messages as normal `jido.ai.request` Signals.
- Accept an optional media attachment as a multimodal content part.
- Run model work outside the LiveView event callback.
- Render ordered model start, chunk, completion, and failure Signals.
- Commit only the final assistant message to the Agent-owned Session.
- Rebuild public chat history from the committed Session after reconnect.
- Show waiting, failed, cancelled, timed-out, uncertain, and committed Turn
  states.
- Use a deterministic local inference client by default.
- Run without a live model provider or network access.

The example can use `Jido.Agent.View` for safe assistant and operation metadata,
but chat does not depend on it. The application must project public messages
from the Session and must not send a complete AgentServer snapshot to the
browser.

The LiveView is a transient client of the Agent. A lost socket can lose
uncommitted stream chunks, but it can recover the final committed conversation.
The example must state this limit. It must also state that a conversation ID is
not an authorization credential.

The example directory includes the Playground script and LiveView tests for a
normal exchange, reconnect, model failure, and ordered streaming. It must not
copy old APIs that returned the full Agent from each call.

## Part V: Operate and integrate

### 25 Operations and Integrations

Purpose: Define production boundaries and offline integration contracts.

Proposed lessons:

1. Production configuration and shutdown.
2. Persistence adapter selection.
3. Secrets and credential boundaries.
4. External adapter boundaries with deterministic local services.
5. Passive Agent Fleet benchmarks and load checks.
6. Security, authorization, and sandbox limits.
7. Distribution boundaries.
8. Offline AI provider configuration and failure handling.

Fleet benchmarks must publish the runtime and hardware environment, logical
and resident Agent counts, concurrency, store configuration, activation and
passivation throughput, latency percentiles, and memory use. Scale claims must
cite measured results from a reproducible run.

ReqLLM owns provider credential resolution. Jido has no separate provider-key
setting. Examples must read credentials from runtime configuration, environment
variables, or an application secret provider. They must not put a secret in a
Signal, Flow input, Agent state, Session, Thread, tool result, snapshot, or
telemetry field.

Model request `options` are normal Flow input. They are not a secret channel.
Provider keys must stay outside Agent defaults and per-request options.

Redaction is defense in depth, not proof that a value is safe. Credential
examples must cover least privilege, tenant scope, rotation, missing and invalid
credentials, log redaction, and safe error output. Tests use fake credentials.
The examples do not accept live credentials.

External integration examples use deterministic local services behind the
same application ports. They must state what a real adapter must supply. They
must not contact a network service.

## Structure decisions

The outline uses these decisions:

1. The first-hour path uses one application across six lessons.
2. Values and validation stay with the contracts that use them.
3. Flow patterns stay inside Flow Execution.
4. Dynamic Agent composition and declared Agent topology use separate chapters.
5. `Jido.Durable` and durable AgentServer hosting stay in one chapter.
6. The same sequence provides learning material and integration tests.
7. Collaborative Agent Systems uses several examples.
8. All examples run offline. External boundaries use deterministic local
   services and state what real adapters must supply.
9. Application-level AI patterns use normal Jido Flows, not new core APIs.
10. Official MCP client support stays in `jido_connect` and enters Jido through
    `Jido.AI.ToolSource`.
11. Advanced AI reasoning strategies use grouped comparison lessons.
12. The Phoenix Playground LiveView chat is an offline application pattern.
    Jido core stays framework-neutral.
13. Multimodal examples use content parts and application Actions over the
    existing inference-client contract.
14. Model resilience is explicit. Only strategies that implement retry and
    fallback can claim those behaviors.
15. Secrets stay at the application and runtime boundary. They do not enter
    portable Jido data.
16. Context compaction and long-running Session rollover are application Flows,
    not hidden core behavior.
17. Advanced examples dogfood current public contracts and record concrete core
    gaps instead of hiding them.
18. Distinct Jido strengths use executable headline examples, injected
    failures, and measured evidence.

## Proposed example contract

After the table of contents is approved, each supported example should have:

- One stated public contract.
- One self-contained example directory.
- One documented command that a reader can run.
- Behavior tests for the main path and the stated failure cases.
- Expected output or expected state.
- A Limits section that states what the example does not prove.
- A Core Fit and Gaps section with reproducible evidence.
- No dependency on private test-support APIs in reader-facing source.

For each advanced example, its documentation and tests must identify:

- The logical owner.
- The process owner.
- The canonical state owner.
- The commit point.
- The data that is persisted.
- The retry boundary.
- The idempotency rule.
- The injected failure.
- The recovery result.
- The limits and non-guarantees.

Tests must check each item that has an observable result. Documentation must
explain items that cannot be checked directly. Recovery is a tested contract,
not an assumed runtime property.

All runner commands must run in the offline example gate. No example runner
can require a live provider, paid API, credential, or network service.
