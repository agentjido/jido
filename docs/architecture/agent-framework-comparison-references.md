# Agent framework comparison references

This document is a research reference for the Jido package vision. It does not define the Jido architecture. It records external designs that can test the vision.

The review snapshot is 2026-11-02. It uses current Hex packages, official source repositories, and relevant repositories from Mike Hostetler's public GitHub stars. Package versions will change after this date.

## Why these references matter

The Elixir agent ecosystem now contains several different product types under the word "agent":

- a model and tool loop;
- a supervised AI conversation;
- a durable workflow or graph;
- a multi-agent coordinator;
- a protected code-execution runtime;
- a general actor runtime with optional AI.

Jido must state which problems it owns. It must also state which problems belong to `Jido.AI`, another Plugin, or an application.

## Direct comparison set

| Reference | Version reviewed | Primary product shape | Main comparison question for Jido |
|---|---:|---|---|
| [Sagents](https://hex.pm/packages/sagents) · [source](https://github.com/sagents-ai/sagents) | 0.20.0 | Interactive AI AgentServer with middleware, supervision, persistence, and LiveView support | Can Jido give a simpler first-hour experience while it keeps the core AI-neutral? |
| [Aikido](https://github.com/barnabasJ/aikido) | 0.1.0 source | Independent Jido fork built on Ash resources, Spark DSLs, and a durable OTP runtime | Which Jido boundaries improve or weaken when Ash actions become the public Agent interface? |
| [Alloy](https://hex.pm/packages/alloy) · [source](https://github.com/alloy-ex/alloy) | 0.13.0 | Small model and tool harness | Which AI concerns must stay out of the actor core? |
| [Condukt](https://hex.pm/packages/condukt) · [source](https://github.com/tuist/condukt) | 1.14.0 | Supervised AI sessions with sandbox and network policy | Where does protected execution end and the actor runtime begin? |
| [GenAgent](https://hex.pm/packages/gen_agent) · [source](https://github.com/genagent/gen_agent) | 0.12.0 | Long-running LLM sessions modeled as OTP state machines | Can AgentServer make lifecycle states as explicit as its behavior states? |
| [BeamWeaver](https://hex.pm/packages/beam_weaver) · [source](https://github.com/caudena/beam_weaver) | 1.0.0 | AI Agents plus graph workflows, memory, checkpoints, and tracing | How does Jido keep Flow general when AI also needs graphs and durable execution? |
| [ExAgent](https://hex.pm/packages/exagent) · [source](https://github.com/akorda-software/exagent) | 2.2.3 | Layered loop, server, store, and multi-agent session framework | Can Jido show a similarly clear path from direct execution to a managed runtime? |
| [Nous](https://hex.pm/packages/nous) · [source](https://github.com/nyo16/nous) | 0.20.0 | Batteries-included AI framework | Which included capabilities improve adoption, and which ones make the core too large? |
| [Legion](https://hex.pm/packages/legion) · [source](https://github.com/software-mansion/legion) | 0.6.0 | AI runtime that writes and runs code in a sandbox | Are Actions sufficient for tools, or must an optional Plugin support protected code execution? |
| [Hayata](https://hex.pm/packages/hayata) · [source](https://github.com/zgbjgg/hayata) | 2.0.0 | Erlang/OTP graph runtime with Mnesia checkpoints | What are the exact crash and uncertain-effect rules for a Flow Turn? |
| [Synapse](https://hex.pm/packages/synapse) · [source](https://github.com/nshkrdotcom/synapse) | 0.1.1 | Signal bus, workflow engine, and configurable multi-agent runtime | Can downstream packages build a full orchestration system without adding paths around Jido boundaries? |
| [Imp](https://hex.pm/packages/imp) · [source](https://github.com/deepfates/imp) | 0.18.1 | Declarative and optimizable language-model programs | Can AI programs remain measurable data while AgentServer stays a lifecycle shell? |

The GitHub stars review supplied Alloy, Condukt, BeamWeaver, Legion, Hayata, Synapse, and Imp. Sagents and Aikido were named comparison targets. The Hex search supplied the other direct peers. Aikido is installed from its source repository and was not a Hex package in this review.

## Sagents: the main developer-experience benchmark

Sagents has the largest direct overlap with the planned Jido AI experience.

Its public model includes:

- an AgentServer for each running agent;
- dynamic supervision and registry-based process discovery;
- explicit execution modes that compose reusable run steps;
- middleware for tools, human approval, sub-agents, summarization, file access, and process context;
- optional persistence for Agent state and display messages;
- PubSub events and Phoenix Presence integration;
- a setup generator for conversation persistence and coordination;
- a separate LiveView debugger;
- optional Horde-based distribution.

Sagents gives Jido useful tests:

1. A developer can start with one supervised agent and add middleware as needed.
2. Human approval pauses and resumes both parent and child agents.
3. The runtime publishes enough semantic events for a live debugger.
4. The setup generator removes repeated persistence and Phoenix wiring.
5. Agent state and user display messages have different storage needs.
6. Local and distributed process discovery use one public model.

Jido must not copy the Sagents boundary without review. Sagents is an interactive AI framework built on LangChain. Jido is a general actor runtime, and AI is one first-party Plugin. The comparable Jido concepts are:

| Sagents concept | Jido concept to test | Boundary risk |
|---|---|---|
| Execution mode and steps | `Jido.Flow` and Actions | Two competing behavior composition systems |
| Middleware | Plugin, Flow middleware, or Action wrapper | One generic hook chain with unclear ownership |
| AgentServer | `Jido.AgentServer` | AI-specific state or lifecycle in the actor shell |
| Human approval interrupt | Runtime wait plus a policy Plugin | Approval coupled only to model tool calls |
| Agent persistence | Agent state and Persistence contract | Conversation storage treated as all actor storage |
| Display-message persistence | Session and Thread projections | UI data placed in canonical Agent state |
| Live debugger | semantic events, status, history, and tracing | A debugger that depends on private process state |
| Horde distribution | Jido instance distribution policy | A distribution promise without clear recovery limits |

The strongest lesson is not "add middleware." The lesson is to make complete capabilities easy to add and easy to inspect.

## Aikido: the direct architectural fork

Aikido started as a Jido fork and is now an independent project. It uses Ash resources, typed Ash actions, Spark DSLs, Signals, and a shared OTP runtime. AI is optional and uses ReqLLM. DurableServer supplies keyed activation, snapshots, and recovery.

Its public model includes:

- an Ash resource for an Agent definition;
- generated Ash domain actions for Agent lifecycle and state access;
- mounted slices that add routed public actions;
- one shared runtime supervision tree for all Agents in an Aikido instance;
- Agents, teams, and nested teams through the same action interface;
- runtime-supplied AI models and tools;
- stable Agent identity across process replacement;
- snapshot policy for permanent and temporary Agents;
- explicit recovery limits for in-flight tools and waiting Lua work.

Aikido is important because it makes different choices with concepts that came from the same starting point:

| Design question | Aikido choice | Jido question |
|---|---|---|
| Public Agent API | Generated Ash domain actions | Should Jido expose one native Agent API, integrate through Ash, or support both? |
| Definition model | Ash resources and Spark DSLs | Can Jido keep simple definitions accessible without making Ash knowledge mandatory? |
| Runtime instance | Shared DurableServer supervision | Does `Jido.Instance` define the same clear ownership and startup boundary? |
| Composition | Mounted slices and teams | Do Plugins, Flows, and Catalog cover these composition needs without a second model? |
| Persistence | Keyed activation and snapshots | What are the activation, retention, checkpoint, and deletion rules for a durable Jido Agent? |
| AI | Optional extension with runtime tools | Can `Jido.AI` stay optional while it uses the same Action, Signal, and lifecycle contracts? |
| Recovery | No replay of in-flight tools and no resume of a waiting Lua VM | How does Jido report and resolve each uncertain or non-resumable Turn? |

Aikido creates a useful developer-experience comparison. Ash can give developers validation, generated functions, domain organization, policies, and introspection. It also adds Ash and Spark as required concepts. Jido must test both approaches with the same Agent example and measure setup code, error quality, inspection, extension work, and runtime clarity.

## Scope checks from smaller frameworks

### Alloy

Alloy calls itself a harness, not a framework. It owns the model and tool loop. It leaves sessions, persistence, scheduling, hosted queues, dashboards, and user interfaces to the application. Its supervised agent support moved to a separate package.

This is the main scope check for `Jido.AI`:

- model-provider protocol work belongs in the AI capability;
- core Agent and AgentServer must not depend on a model loop;
- memory, sessions, persistence, and scheduling must not become one hidden AI subsystem;
- an application must be able to use Jido without any AI configuration.

### ExAgent

ExAgent publishes a clear four-layer path:

1. a one-shot loop;
2. a supervised stateful server;
3. durable snapshots and resume;
4. coordinated multi-agent sessions.

This is a strong developer-experience reference. Jido needs a clear direct-to-managed path, even though its layers are different:

1. Action;
2. Flow;
3. direct Agent Turn;
4. supervised AgentServer;
5. durable and distributed policy.

### GenAgent

GenAgent separates lifecycle mechanics from Turn semantics. It uses `:gen_statem` for long-running model sessions. It also separates provider backends and multi-agent ensembles from the core package.

Jido is one package by design, but it can keep the same internal discipline:

- AgentServer owns queue, cancellation, waits, and lifecycle states;
- a Flow owns Turn semantics;
- `Jido.AI` owns model session semantics;
- Plugins add capabilities without changing the AgentServer state machine.

### Nous

Nous is the main batteries-included counterexample. It combines providers, tools, structured output, hooks, Plugins, human approval, memory, workflows, teams, knowledge, testing, supervision, persistence, and LiveView support.

This tests the Jido included-Plugin policy. A large integrated feature set can improve first use. It can also make ownership, startup cost, and extension rules difficult to understand. Jido must publish the included capability list and keep each capability removable from an Agent.

## Workflow and recovery references

### BeamWeaver

BeamWeaver combines typed tools, Agents, graphs, human approval, memory, checkpoints, durable execution, middleware, testing, and tracing.

It tests the Flow boundary. Jido must avoid three similar graph concepts for core behavior, AI reasoning, and durable work. The preferred model remains:

- Flow is the general behavior graph;
- AI reasoning is a Flow recipe;
- durable execution is a runtime policy over a Flow, not a second behavior language;
- memory is an explicit capability, not implicit Flow state.

### Hayata

Hayata uses OTP processes for an Agent, graph nodes, edges, reducers, and watchers. It stores invocation checkpoints and task outcomes in Mnesia. Its documentation states that an uncertain task is not silently run again after recovery.

This tests two Jido decisions:

- Flow nodes must not require one process for each abstraction;
- AgentServer recovery must distinguish safe retry, known completion, and uncertain external effect.

Hayata also reinforces the rule that a node returns state updates. The runtime applies them after successful execution.

### Synapse

Synapse is important because it uses signals, workflows, persistence, Agent configuration, and Jido plan compilation in one downstream system.

It tests Jido as a platform boundary:

- Signals must be sufficient for domain protocols;
- Flow and Actions must be sufficient for orchestration;
- Catalog must let a package contribute domain definitions;
- persistence and telemetry must be usable without private Jido APIs;
- downstream systems must not need a second Agent runtime around Jido.

## Protected execution references

### Condukt

Condukt separates declarative workflow steps from Agent decisions. It also treats sandboxes, network policy, secret handling, backpressure, cancellation, and child agents as primary runtime concerns.

The workflow split supports the Jido vision: use a Flow for named behavior and use AI for decisions that cannot be fixed in advance.

The security design is a boundary warning. AgentServer process isolation is not a sandbox. Protected code execution, network policy, and secret injection need a separate execution capability with a clear authority contract.

### Legion

Legion lets a model write a Lua program that calls approved application facades. The program runs in a sandbox. Tools own authorization, and rate limits apply before a Turn starts.

Legion tests the Action boundary:

- an Action can remain the approved application facade;
- a protected interpreter can be an optional caller of Actions;
- the interpreter must not bypass validation, authorization, budgets, or telemetry;
- Jido must not describe ordinary BEAM process isolation as safe execution of untrusted code.

## Declarative program reference

Imp treats model calls as declared and typed functions that can be measured and improved. A program can run directly or as a supervised process. It reports a tool call with an uncertain result instead of silently retrying it.

Imp tests whether Jido can keep definitions inspectable:

- Flow plans must be data that tools can inspect;
- AI prompts, tools, and reasoning policy need stable identities for evaluation;
- runtime events must support measurement without changing behavior;
- optimization must produce a new definition or revision, not mutate a running Agent invisibly.

## Jido ecosystem references

These packages are not neutral competitors. They show what external Jido packages already need from the core.

| Reference | Design pressure on the consolidated package |
|---|---|
| [Jido Composer](https://hex.pm/packages/jido_composer) · [source](https://github.com/lostbean/jido_composer) | Nested deterministic workflows, adaptive orchestrators, human gates, checkpoints, and runtime skill assembly must map to Flow, AI, Catalog, and Persistence without a second core model. |
| [Jidoka](https://hex.pm/packages/jidoka) · [source](https://github.com/agentjido/jidoka) | Hosted Agent products need strict Session, Server, Storage, protocol, and workspace boundaries. |
| [Oh My Jido](https://github.com/mattneel/oh_my_jido) | An embedded coding Agent needs host control, tool authority, and stable runtime events. |
| [Jizoku](https://github.com/agentjido/jizoku) | Durable workflows need a clear contract with Flow and Persistence. |

These uses support the application-wide Catalog goal. An extension package must be able to publish Actions, Flows, Agent definitions, Plugins, and other capability definitions without editing the host application.

## Secondary Hex watch list

These packages are useful for later focused reviews. They are not in the direct comparison set because they duplicate a tested product shape or focus on a narrower boundary.

- [Normandy](https://hex.pm/packages/normandy): schemas, guardrails, distributed sessions, and multi-agent coordination.
- [Wardrik Core](https://hex.pm/packages/wardrik_core): durable Agents, approval, policy, budget, event, vault, trigger, and workspace packages.
- [Lemon Agent](https://hex.pm/packages/lemon_agent): agent loop, event bus, router, memory, channels, and gateway split across packages.
- [Planck Agent](https://hex.pm/packages/planck_agent): supervised model and tool loop with PubSub events.
- [Praxo Core](https://hex.pm/packages/praxo_core): small embeddable Agent framework.
- [Rho](https://hex.pm/packages/rho): compact agent core with sessions, tools, and context compaction.
- [Skill Kit](https://hex.pm/packages/skill_kit): tools, skills, and sub-agent delegation.
- [Jido Composer](https://hex.pm/packages/jido_composer): Jido-based multi-agent workflows and checkpoints.
- [Jidoka](https://hex.pm/packages/jidoka): Jido-based durable Turn runtime and hosted Agent product.

## Older or experimental starred references

These repositories remain useful as idea sources. They do not have the same review priority as the current Hex packages.

- [Agens](https://github.com/jessedrelick/agens)
- [Magus](https://github.com/poffdeluxe/magus)
- [SwarmEx](https://github.com/nrrso/swarm_ex)
- [Agentic](https://github.com/tensiondriven/agentic)
- [Shifts](https://github.com/aaronrussell/shifts)
- [agents.erl](https://github.com/arthurcolle/agents.erl)
- [Automata](https://github.com/upstarter/automata)
- [LLMAgent](https://github.com/i365dev/llm_agent)

## Cross-framework conclusions

The comparison supports these working conclusions:

1. **Jido needs a clear product category.** It is a configurable actor runtime. It is not only a model and tool loop.
2. **AI must remain a capability.** `Jido.AI` can be rich, but the Agent and AgentServer core must stay useful without it.
3. **Flow must remain the behavior language.** Jido must not add separate workflow, reasoning graph, and durable graph models.
4. **AgentServer must remain a lifecycle shell.** It owns serialization, cancellation, waits, commit, recovery, and process lifecycle. It does not own domain or AI decisions.
5. **Human approval is a general runtime wait.** AI tool approval is one use of a reusable policy and continuation mechanism.
6. **Security needs its own boundary.** Process isolation, validation, authorization, and code sandboxing are different guarantees.
7. **Persistence must describe uncertainty.** Recovery must not silently repeat an external effect with an unknown result.
8. **Observability is part of the public contract.** A debugger must use stable semantic events, status, and history instead of private process inspection.
9. **Developer experience needs a direct path and a managed path.** A developer must test behavior without a process, then use the same behavior in AgentServer.
10. **Included Plugins need strict ownership.** Batteries help first use only when each capability has clear state, lifecycle, dependencies, and removal rules.

## Comparison tests to add to the vision

Jido should be able to answer these tests with examples or executable evidence:

1. Build the same interactive AI agent in Jido and Sagents. Compare setup code, required concepts, approval flow, persistence, and debugging.
2. Build the same durable Agent in Jido and Aikido. Compare the public API, required framework concepts, activation, snapshot, recovery, and error messages.
3. Build the same one-shot tool loop in `Jido.AI` and Alloy. Explain every extra Jido concept and guarantee.
4. Run one Agent directly, then under AgentServer. Show identical Flow semantics.
5. Pause a nested Flow for human approval, restart the AgentServer, and resume once without repeating the protected effect.
6. Add a sandbox Plugin that can call approved Actions but cannot bypass Catalog policy or Action validation.
7. Show one non-AI actor and one AI Agent using the same AgentServer lifecycle and telemetry vocabulary.
8. Add an extension package through Catalog and use its Action or Flow without host registration code.
9. Explain one failed Turn from Signal receipt to Flow node, Action result, state commit decision, recovery state, and final status.
