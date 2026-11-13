---
title: Jido.AI component
status: current
last-reviewed: 2026-11-13
---

# Jido.AI component

Purpose: Add graph-first model reasoning, tools, provider calls, policy, usage,
and conversation projection to a Jido Agent.

Review result: The parent boundary and all eight standard reasoning
sub-components are confirmed. The review found one input defect and two design
reduction opportunities.

## Parent public contract

The parent has no `Jido.AI` facade module. It is a parent namespace with these
public entries:

- `Jido.AI.Agent` adds one `jido.ai.request` route and the AI Plugin to a
  normal Agent.
- `Jido.AI.Reasoning` inspects and compiles the root reasoning Flow.
- `Jido.AI.InferenceClient` defines the model-operation adapter contract.
- Context, Budget, Usage, RequestPolicy, Toolset, ToolSource, Skill, and
  ToolResult own model and tool boundary values and rules.
- `Jido.AI.Thread.Projection` converts a Session and Thread into bounded model
  context.

`Jido.Session` and `Jido.Thread` remain separate components. Telemetry remains
the system observation component. ReqLLM is the model data and provider
boundary used by this component.

## API use

An AI Agent route points directly to a normal `Jido.Flow`. Shared Actions build
one request turn, project conversation history, call the selected inference
client, enforce limits, record attempts, and create one terminal result.
Reasoning Flows use these Actions and do not use a hidden strategy process.

The current Covenant surfaces divide the parent into agent authoring,
conversation projection, model execution, observability, tools, the shared
turn, ReAct, and the other standard strategies.

## Duplication and reduction review

Seven standard strategy modules repeat the common request schema and the same
start, guard, invoke, and finalize graph. Algorithm of Thoughts and Chain of
Draft differ mainly in identity, instructions, token defaults, output schema,
and completion projection. Their ModelRound Flows also repeat the same steps.

Retain each public strategy module and Flow ID. Extract private builders for
the common request schema, root graph parameters, and simple structured model
rounds. This reduces drift without merging the public strategy contracts.

`Jido.AI.InferenceClient.Selection` repeats the complete callback list from
the behavior and requires every client to implement all 22 operations. This
makes small text-only test clients delegate 21 unrelated functions. The
selection check can use the behavior callback metadata. The client contract
can also define capability groups or documented optional callbacks.

## Elixir design

Reasoning recipes are ordinary Flow modules. This makes graph shape,
validation, persistence, waits, and execution visible to the rest of Jido.
Actions own provider and tool side effects through the normal Exec boundary.
No AI-specific GenServer or workflow runtime exists.

The parent namespace is acceptable without an empty facade because its public
entry modules have distinct behavior. Documentation must present those entry
modules as the parent surface.

## Adaptive sub-component

`Jido.AI.Reasoning.Adaptive` makes one local choice and expands to one of the
other seven standard Flows. An explicit `strategy` value bypasses the text
heuristic. It does not call a model by itself.

Result: Retain it as an independently usable routing Flow.

Open defect A1: Its input schema accepts a list of arbitrary maps. The default
heuristic passes each `text` value to `Enum.map_join/3`. A non-string value
raises `Protocol.UndefinedError`. The public Action must ignore non-text
content or return a normal validation error.

## Algorithm of Thoughts sub-component

`Jido.AI.Reasoning.AlgorithmOfThoughts` makes one structured model call. It
returns an operation sequence and answer through the common result envelope.

Result: Retain the public Flow and its output contract. Share its private
single-call graph structure with the other simple strategies.

## Chain of Draft sub-component

`Jido.AI.Reasoning.ChainOfDraft` makes one bounded structured model call. It
returns short drafts and one answer.

Result: Retain the public Flow. Its implementation is almost the same as
Algorithm of Thoughts and is the strongest extraction candidate.

## Chain of Thought sub-component

`Jido.AI.Reasoning.ChainOfThought` makes one structured model call. It returns
ordered public reasoning steps and one conclusion. It does not expose hidden
provider reasoning state and it does not run tools.

Result: Retain the public Flow and share its common single-call machinery.

## Graph of Thoughts sub-component

`Jido.AI.Reasoning.GraphOfThoughts` uses two model rounds. The first creates
nodes and edges. The second synthesizes an answer. Validation rejects edges
that refer to a missing node.

Result: Retain it as a distinct two-stage graph.

## ReAct sub-component

`Jido.AI.Reasoning.ReAct` owns the model and tool loop. It validates tools,
keeps model order for parallel calls, supports durable approval waits, detects
repeated tool cycles, records tool attempts, and enforces tool and model limits.

Result: Retain it as the canonical tool-using reasoning component. Its graph
and durable wait contract are different from all other strategies.

## Tree of Thoughts sub-component

`Jido.AI.Reasoning.TreeOfThoughts` uses three model rounds to generate,
evaluate, select, and synthesize candidate thoughts.

Result: Retain it as a distinct bounded branching graph.

## TRM sub-component

`Jido.AI.Reasoning.TRM` uses three model rounds for one draft, critique, and
revision cycle.

Result: Retain it as a distinct bounded refinement graph.

## Open findings

### A1 — Adaptive can raise on accepted content

Confirmed with a local probe. `%{input: [%{text: %{bad: true}}]}` passes the
Action's broad map boundary and raises `Protocol.UndefinedError` during
selection.

### A2 — Inference client capability is all-or-nothing

Selection requires all 22 callbacks for every client. Text-only and test
clients must supply unrelated media, speech, OCR, embedding, rerank, and
evaluation functions. The behavior and Selection also keep two copies of the
callback list.

### A3 — Common strategy structure is repeated

The standard strategies repeat request schemas and graph stages. This is not a
public contract defect. It is a maintenance and drift risk. Use private shared
builders and keep all public modules and Flow identities.

## Proof

The 2026-11-13 focused command ran the complete `test/jido/ai` tree as part of
a 502-test command. All tests passed. The review traced all AI Covenant owners,
the AI Agent authoring path, inference-client selection, shared turn Actions,
tool and conversation boundaries, and all eight reasoning namespaces.

The focused suite used mock or offline inference. It did not call a live model
provider. The Adaptive defect used a separate local probe. No production fix
was part of this review.

## Sources

- [AI Agent authoring](../../lib/jido/ai/agent.ex)
- [Reasoning inspection](../../lib/jido/ai/reasoning.ex)
- [Inference client](../../lib/jido/ai/inference_client.ex)
- [Inference client selection](../../lib/jido/ai/inference_client/selection.ex)
- [Adaptive](../../lib/jido/ai/reasoning/adaptive.ex)
- [Algorithm of Thoughts](../../lib/jido/ai/reasoning/algorithm_of_thoughts.ex)
- [Chain of Draft](../../lib/jido/ai/reasoning/chain_of_draft.ex)
- [Chain of Thought](../../lib/jido/ai/reasoning/chain_of_thought.ex)
- [Graph of Thoughts](../../lib/jido/ai/reasoning/graph_of_thoughts.ex)
- [ReAct](../../lib/jido/ai/reasoning/react.ex)
- [Tree of Thoughts](../../lib/jido/ai/reasoning/tree_of_thoughts.ex)
- [TRM](../../lib/jido/ai/reasoning/trm.ex)
- [Strategy obligations](../../test/contracts/jido_ai/strategies.obligations.md)
- [ReAct obligations](../../test/contracts/jido_ai/react.obligations.md)
