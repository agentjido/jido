# Agent delegation protocol

Date: 2026-10-26
Status: Exploration
Owner: Jido core
Implementation: Not started
API commitment: None

## Purpose

Define how one AgentServer can delegate work to another AgentServer from a
Flow. Keep each Flow and its durable state local to its owning AgentServer.
Use Signals for all work that crosses an AgentServer boundary.

This note records a possible direction. It does not define an approved API or
an implementation schedule.

## Problem

Jido can define an Agent topology and connect AgentServer processes at runtime.
A Flow can also define a logical program for one Agent. Jido needs a clear way
for that Flow to ask another Agent to do work.

The delegation boundary must support these cases:

1. Send work and continue without a reply.
2. Send work, continue local work, and wait for the reply later.
3. Send work and wait for the reply at once.
4. Recover the caller after a crash without moving the caller Flow to another
   AgentServer.
5. Keep correlation and causation data for each request and reply.

Jido must not send a Runic `Runnable` to another AgentServer. The target Agent
must receive a Signal and start or continue its own local work.

## Main rule

Distribute graph work. Do not distribute graph ownership.

Runic and Jido Flow own the logical program inside one Agent. Jido owns Agent
identity, topology, process resolution, Signal delivery, local durability, and
failure handling between Agents.

## Package boundaries

### `jido_action`

- Owns the general Flow model and in-memory execution.
- Defines general suspension and continuation contracts when they are useful
  outside Agent delegation.
- Does not own Agent lookup, remote delivery, or durable orchestration.

### `jido_signal`

- Owns the Signal envelope.
- Owns serialization, routing data, dispatch, and the local Signal bus.
- Carries correlation and causation identifiers.
- Does not own request lifecycle state.

### `jido`

- Owns `Agent`, `AgentServer`, topology, directives, and the OTP runtime.
- Resolves an Agent Address to a live destination.
- Owns the durable request record, outbox work, reply inbox, timeout policy,
  and Flow resume operation.
- Owns the Agent-specific Flow integration described in this note.

### `jido_ai`

- Uses these operations for multi-Agent reasoning.
- Does not own the general delegation protocol.
- Does not send model-specific graph state across the Agent boundary.

## Proposed operations

The names below are working names. Their behavior is more important than their
final DSL form.

### `agent_cast`

Send a request Signal and continue the local Flow. Do not create an expected
reply.

Success means that Jido accepted the send operation into its local delivery
boundary. It does not mean that the target completed the work.

This operation is similar to `GenServer.cast/2`, but delivery must still use a
Jido Signal and the Jido topology.

### `agent_request`

Create a durable request, send its Signal, and continue the local Flow. Return
a local request reference that a later graph step can use.

The caller must register the expected reply before it sends the request. This
order prevents a fast reply from arriving before Jido knows where to store it.

### `await`

Wait for a reply to a prior request.

If the reply is already in the caller inbox, return it at once. If it is not
present, suspend the local Flow. A matching reply or timeout can resume the
Flow later.

`await` is a general gate concept. Agent delegation is one source of events
that can open the gate.

### `agent_call`

Create a request and wait for its reply at once. This is equivalent to
`agent_request` followed by `await`.

The operation is synchronous in Flow terms. The next graph step does not run
until the reply or timeout result is available. It must not block the
AgentServer process while it waits.

This operation is similar to `GenServer.call/3` at the authoring surface. Its
runtime behavior is a durable Signal request and reply, not a direct process
call.

## Illustrative Flow shape

This example shows intent only. It is not an approved DSL.

```elixir
flow do
  step :prepare, PrepareQuestion

  agent_request :critic_request,
    agent: :critic,
    input: result(:prepare),
    timeout: :timer.seconds(30)

  step :local_analysis, AnalyzeLocally

  await :critic_reply,
    request: result(:critic_request)

  agent_call :editor_reply,
    agent: :editor,
    input: result(:critic_reply),
    timeout: :timer.seconds(30)

  step :finish, BuildAnswer
end
```

The same operations can support a multi-Agent reasoning chain. Each Agent has
its own Flow. The parent Flow controls the order of requests and gates. It does
not control the target Agent's internal graph.

## Request and reply identity

Each request needs these identities:

- A stable local request reference for Flow results and persistence.
- A request Signal ID for idempotent delivery and duplicate detection.
- A correlation ID for the complete logical exchange.
- A causation ID on the reply that points to the request Signal ID.
- Caller and target Agent identities.

A retry must keep the same logical request identity. It must not create a new
logical request only because transport delivery was uncertain.

The reply Signal must include enough data for the caller to find the pending
request without using the target process identifier.

## Runtime sequence

For a request that expects a reply:

1. The caller prepares the request Signal.
2. The caller records the pending request and the delivery work in one local
   durable transition.
3. Jido sends the request after that local commit.
4. The target AgentServer receives the Signal and runs its own local turn.
5. The target commits its local result.
6. The target sends a reply Signal after its local commit.
7. The caller stores the reply in its local inbox.
8. An active or later `await` consumes the reply and resumes the caller Flow.

There is no distributed transaction between the two AgentServer processes.
Each AgentServer owns only its local commit.

## Why a normal Directive is not sufficient

A normal post-turn Directive can send work after a completed turn. An
`agent_call` can suspend the Flow before that Flow has completed. Jido therefore
needs a host-level request effect or durable outbox operation that is visible
while the Flow is suspended.

The target can use its normal post-commit effect boundary to send the reply.
The caller needs a durable record that connects its suspended continuation to
the expected reply.

This distinction must be clear before implementation starts.

## Durability and failure behavior

### Caller crash before local commit

No request exists. Jido must not send it.

### Caller crash after local commit and before send

The durable outbox retains the request. Jido sends it after recovery.

### Duplicate request delivery

The target uses the stable request Signal ID or request identity to detect a
duplicate. The target must not repeat non-idempotent work without an explicit
policy.

### Target crash before local commit

The target does not publish a successful reply. Its normal recovery policy
decides if it retries the local turn.

### Target crash after local commit and before reply send

The target's local post-commit delivery record must retain the reply work, or
the target must be able to reconstruct it from its committed turn.

### Reply arrives before `await`

The caller stores the reply. A later `await` finds it and continues without a
new suspension.

### Caller crash while it waits

The caller restores the pending request, saved continuation, reply inbox, and
deadline from its own persistence data.

### Timeout

The caller records a local timeout result and resumes its Flow according to
policy. A reply that arrives after the timeout needs an explicit late-reply
policy. The first version should record and ignore it by default.

## First implementation limit

Keep the first version small:

- One exact target Agent Address.
- One request Signal.
- Zero replies for `agent_cast`.
- One expected reply for `agent_request` and `agent_call`.
- One local deadline and timeout result.
- One reply value or one structured error value.
- Durable caller state and local outbox behavior.
- Durable target turn behavior through existing Jido rules.
- Correlation, causation, and basic telemetry.

Do not include these features in the first version:

- Broadcast requests.
- Quorum or first-success requests.
- Multiple replies or reply streams.
- Distributed transactions.
- Transfer of Flow, Runic graph, or `Runnable` ownership.
- Remote target graph inspection.
- Automatic reasoning graph composition at request time.
- Cross-Agent cancellation guarantees.

## Test cases required before a public API

1. `agent_cast` sends one Signal and the caller continues.
2. `agent_request` lets local graph work run before `await`.
3. `agent_call` suspends graph progress without blocking the AgentServer.
4. A reply that arrives before `await` is not lost.
5. A caller restart restores a pending wait.
6. An outbox retry does not create a second logical request.
7. A duplicate request does not repeat protected target work.
8. A target error becomes a structured reply result.
9. A timeout resumes the caller exactly once.
10. A late reply follows the defined policy.
11. Correlation and causation identifiers remain stable through retries.
12. Two concurrent requests from one caller cannot consume each other's reply.

## Open questions

1. Should `agent_request` return a public request structure or an opaque
   request reference?
2. Does the existing Flow suspension contract contain all data that a durable
   `await` needs?
3. Where should the caller store pending requests, buffered replies, and
   deadlines in the current persistence model?
4. Can the current outbox and Directive machinery expose the required
   pre-suspension effect boundary, or does Jido need a new host effect type?
5. What target references can the first version accept: Agent ID, topology
   alias, route name, or another stable reference?
6. What structured values represent unavailable targets, target errors,
   timeouts, rejected work, and uncertain delivery?
7. What admission, permission, and back-pressure checks run before dispatch?
8. How long can an unconsumed reply remain in the caller inbox?
9. Does `await` belong in the general Flow vocabulary or only in the Jido host
   integration?
10. Which telemetry events show request creation, dispatch, receipt, reply,
    resume, timeout, retry, and duplicate handling?

## Decision conditions

Do not start implementation until these conditions are true:

1. A complete example shows a useful multi-Agent Flow that needs both a later
   `await` and an immediate `agent_call`.
2. The local persistence record and recovery sequence are clear.
3. The send-after-commit boundary is clear for both request and reply.
4. The first target reference and error contract are clear.
5. The design can use Jido topology and Signals without adding distributed
   graph ownership to Runic.
6. Recovery tests can prove that one logical request resumes one continuation
   no more than once.

## Possible final documentation locations

If Jido accepts this design, move the approved AgentServer protocol to
`docs/design/08_agent-server/` and the topology and delivery rules to
`docs/design/10_runtime-topology/`. Keep AI-specific examples in `jido_ai`.
