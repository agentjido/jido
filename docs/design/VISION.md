> Jido V3 library vision. This document is pending approval.

# Jido V3 library boundary specification

## 1. Identity

Jido is an Elixir library and SDK for building agent systems.

Jido is not a platform, hosted service, application framework, deployment
system, or control plane.

The developer owns the application. The developer selects its architecture,
supervision structure, storage, transport, deployment, and operational model.

Jido provides reusable Agent semantics and runtime components. It does not
take ownership of the system built with them.

## 2. The Bright Line

The Bright Line separates contracts that preserve Agent semantics from choices
that belong to the developer and the surrounding application.

Inside the Bright Line, Jido owns:

- Agent definitions and state.
- Command and Signal evaluation.
- Turn semantics.
- State commit rules.
- Directive production and settlement.
- Agent Server behavior.
- Local runtime components.
- Portable persistence contracts.
- Plugin contracts.
- Public errors.
- Semantic telemetry.
- Developer-facing construction and execution APIs.

Outside the Bright Line, the developer owns:

- Application architecture.
- Domain behavior.
- Process composition above Jido components.
- Storage services and clients.
- Network topology.
- Cluster strategy.
- Deployment.
- Durable workflow orchestration.
- Model and AI-provider integration.
- Transport gateways.
- User interfaces.
- Operational policy.

The Bright Line does not prevent composition. It defines which party owns each
decision.

## 3. Requirement language

This specification uses EARS-style requirements.

- **Ubiquitous:** The Jido library shall...
- **Event-driven:** When an event occurs, the Jido library shall...
- **State-driven:** While a condition is true, the Jido library shall...
- **Optional:** Where a capability is configured, the Jido library shall...
- **Unwanted behavior:** If an invalid or unsafe condition occurs, the Jido
  library shall...

The word **shall** defines a required contract.

## 4. Core purpose

The Jido library shall provide the minimum complete set of contracts required
to build stateful Agent systems in Elixir.

The Jido library shall preserve one shared Agent execution model:

```text
Agent definition
  -> Command or Signal
  -> Turn evaluation
  -> Candidate Agent state
  -> Commit
  -> Post-commit Directives
  -> Settlement
```

The Jido library shall make this model available as composable library code.

The Jido library shall not require the developer to adopt a Jido-owned
application architecture.

The Jido library shall not require a central service, global runtime, hosted
component, or external control plane.

## 5. Developer ownership

The developer shall remain the owner of the complete agent system.

The Jido library shall expose public modules that developers can:

- Call directly.
- Wrap in application modules.
- Place behind application-specific interfaces.
- Compose through standard Elixir functions.
- Start in application supervision trees.
- Configure through normal application configuration.
- Replace at defined adapter boundaries.
- Observe through standard Telemetry handlers.
- Test without starting an external platform.

When a developer needs application-specific policy, the developer shall be
able to place that policy in an ordinary Elixir module outside Jido.

When a public Jido module already provides a sufficient contract, the
developer shall be able to wrap or delegate to that module without using a
Plugin.

Jido shall not require all customization to pass through one universal
abstraction.

## 6. Developer experience

Developer experience is part of the Jido core contract.

The public API shall favor:

- Ordinary functions.
- Explicit structs.
- Behaviours with narrow ownership.
- Standard tagged results.
- Standard OTP child specifications.
- Standard supervision.
- Standard application configuration.
- Stable module documentation.
- Testable components.
- Useful errors at the caller's level of abstraction.

A developer shall be able to understand a Jido component without first
understanding the complete Jido runtime.

A developer shall be able to use a lower-level component without starting
unrelated higher-level components.

A developer shall be able to test Agent behavior through direct execution.

Where live behavior is required, the developer shall be able to start an Agent
Server through standard OTP patterns.

If Jido introduces generated names, private messages, hidden process state, or
implicit global configuration, Jido shall provide a public API that prevents
application code from depending on those details.

The library shall prefer explicit composition over hidden coordination.

## 7. Composition model

Jido supports several forms of composition. These forms have different
purposes and authority.

### 7.1 Ordinary Elixir composition

A developer may wrap, delegate to, or compose Jido modules through normal
Elixir code.

This is the default integration method when the application needs to:

- Present a different public API.
- Add application policy.
- Coordinate several Jido components.
- Transform inputs or outputs outside a Turn.
- Add application supervision.
- Integrate Jido with another library.
- Control application-specific lifecycle behavior.

Jido shall keep its public modules suitable for this form of composition.

### 7.2 Agent authoring

A developer may define an Agent through supported module, Builder, Codec, or
data forms.

All supported authoring forms shall produce the same normalized Agent
definition contract.

Jido shall not force module-only authoring unless a later compatibility
decision explicitly removes another supported form.

### 7.3 Actions and Flows

A developer may implement executable behavior through Actions and Flows.

Actions and Flows shall own executable computation. They shall not own the
Agent commit.

The Agent contract shall define how executable results become candidate Agent
state and Directives.

### 7.4 Plugins

A developer may use a Plugin when a reusable capability must participate in a
defined Agent or Agent Server lifecycle boundary.

A Plugin shall receive only the data and authority required by that boundary.

Plugins shall not be the required mechanism for every form of customization.

A developer shall not need a Plugin to wrap a module, create an application
facade, add supervision, or compose Jido with another library.

### 7.5 Directives

A developer may use a Directive to request work that Jido performs or
coordinates after a successful commit.

When a Turn produces a Directive, Jido shall not dispatch that Directive
before the related commit succeeds.

A Directive shall not serve as a general middleware callback.

### 7.6 Adapters

A developer may configure an adapter when an external service implements a
narrow infrastructure boundary.

An adapter shall replace infrastructure behavior. It shall not redefine Agent
semantics.

The host application shall own external clients, repositories, connections,
and service processes unless the adapter contract explicitly states otherwise.

### 7.7 Telemetry

A developer may attach standard Telemetry handlers to observe Jido behavior.

Telemetry handlers shall not receive authority to change an Agent result,
commit result, or runtime outcome.

Jido shall emit semantic events. The application shall select reporters,
exporters, and observability services.

### 7.8 OTP composition

A developer may place Jido components inside a larger supervision tree.

Jido child specifications shall follow standard OTP contracts.

Jido shall not assume that its supervision tree is the root of the application.

## 8. Agent semantic requirements

### 8.1 Agent value

The Jido library shall define the normalized Agent value.

An Agent value shall contain the state and definition data required for direct
evaluation.

An Agent shall not require a PID, Agent Server, or Jido instance for direct
evaluation.

### 8.2 Turn evaluation

When an Agent receives a valid command, the Jido library shall evaluate one
Turn against one committed Agent state.

When direct and supervised execution evaluate the same valid command against
the same Agent state, both paths shall use the same core Turn semantics.

Operational features such as admission, persistence, cancellation, and
settlement may exist only in supervised execution. These features shall not
silently redefine candidate state production.

### 8.3 Commit

When Turn evaluation succeeds, the Jido library shall produce a candidate
Agent state before that state becomes committed runtime state.

When a live commit succeeds, the Agent Server shall make the committed state
authoritative before it starts post-commit Directive work.

If a commit fails, Jido shall not report the candidate as committed.

The commit guarantee shall apply only to state and durable work that Jido owns.

Jido shall not claim that it can roll back external I/O performed by
application or executable code before commit.

### 8.4 Activation

When a developer starts an Agent Server, Jido shall create a supervised
activation of a logical Agent.

A PID shall identify that activation.

A PID shall not define the durable identity of the logical Agent.

### 8.5 Persistence

Where persistence is configured, Jido shall store and restore committed Agent
state through a public persistence contract.

Jido shall own the portable record format and revision rules.

The configured storage adapter shall own atomic byte-storage operations.

The application shall own the storage service.

### 8.6 Observation

When an important Agent lifecycle transition occurs, Jido shall emit a bounded
semantic event.

If an observation handler fails, Jido shall preserve the defined Agent and
runtime outcome unless the public contract explicitly states otherwise.

## 9. Library boundaries

Jido core may include a contract when all of the following conditions are
true:

1. The contract protects shared Agent semantics or runtime safety.
2. The contract has one clear Jido owner.
3. Direct application composition cannot provide the contract safely.
4. An external implementation would otherwise require Jido private state or
   messages.
5. The contract does not select a product, vendor, or deployment architecture.
6. The contract can have stable public documentation and tests.

If these conditions are not true, the capability shall remain in application
code or another library.

## 10. Excluded responsibilities

The Jido library shall not own:

- The developer's application architecture.
- A hosted Agent service.
- A deployment environment.
- A global Agent registry across independent systems.
- Cluster membership or consensus.
- Fleet placement or rebalance policy.
- Durable business workflow history.
- Product-specific Agent definitions.
- Model-provider policy.
- Browser sessions.
- Transport gateways.
- User interfaces.
- Vendor-specific telemetry infrastructure.

Another Jido ecosystem library may provide one of these capabilities.

Such a library shall use Jido through public contracts. It shall not require
Jido core to become a platform.

## 11. Public-contract test

Before Jido adds a new public abstraction, the proposal shall answer:

1. What developer problem does this solve?
2. Why is ordinary Elixir composition insufficient?
3. Which Jido semantic invariant does it protect?
4. Which Jido component owns it?
5. What authority does it grant?
6. What data does it expose?
7. Can a developer test it without starting unrelated runtime components?
8. Does it preserve standard Elixir and OTP composition?
9. Can ecosystem libraries use it without private Jido knowledge?
10. Does it move application or product responsibility into Jido core?

If the proposal cannot answer these questions clearly, Jido shall not add the
abstraction.

## 12. V3 intent

Jido V3 shall be a complete Agent library, not a complete Agent product.

It shall provide enough structure to make Agent execution consistent, safe,
testable, and composable.

It shall leave enough freedom for developers to design systems that do not
resemble each other.

The central promise is:

> Jido defines the semantics and runtime components of an Agent. The developer
> defines the system that uses them.

The Bright Line protects both sides of that promise:

- Inside the line, Jido provides stable Agent contracts and a high-quality
  Elixir developer experience.
- Outside the line, developers use ordinary Elixir architecture, Jido
  integration contracts, and other libraries to build the system they intend.
