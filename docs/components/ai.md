---
title: Jido.AI component
status: current
last-reviewed: 2026-11-19
---

# Jido.AI component

Purpose: Add graph-first model reasoning, tools, provider calls, policy, usage,
and conversation projection to a Jido Agent.

## Top-level review on 2026-11-19

All four checks are complete for [tracker #453](https://github.com/agentjido/jido/issues/453).
The review used [`6fdc009a` on `release/v3`](https://github.com/agentjido/jido/commit/6fdc009a1edd6261f3e26509fa2905bb9192faa5).
The issues below record impact and acceptance checks.

### Public surface

- [x] `use Jido.AI.Agent` and `Jido.AI.Agent.Plugin` author one
  `jido.ai.request` route to a named or inline Flow. A reasoning block sets
  partial Flow defaults. Static tools are ordered Action and Flow modules.
  The Plugin codec stores registered references and portable defaults.
- [x] Generated `reasoning/0` and `explain/0` inspect the route. `preflight/1`
  accepts a map or keyword list and returns effective parameters, the static
  tool list, and a compiled workflow on success. It can return an error from
  validation or compilation. It does not call a provider. `cmd/3` and
  AgentServer use the normal Agent execution contract. Shared finalization
  produces the `jido.ai.response` data with status, output, IDs, usage,
  budgets, attempts, and Session entries.
- [x] `InferenceClient.Selection.client!/1` selects the Action context
  client, then the `:jido` application setting `:ai_inference_client`,
  then the ReqLLM adapter. An invalid module raises `ArgumentError`.
  The shared model call records this as a model failure. Standard calls use
  `generate_text/3` or `stream_text/3`. The Embed Action uses `embed/3`.
  The remaining callbacks serve application Actions. `Context` holds the
  open, prepared, and completed request. `Context.Snapshot` records a
  portable projection of the attempt.
- [x] `RequestPolicy` keeps Agent instructions, required review, limits,
  and tool restrictions in force in the shared start path. `Toolset` selects
  and resolves tools. A host supplies dynamic tools through
  `:jido_ai_tool_sources`. `ToolResult` projects bounded model content
  from a local outcome. `Skill` is a filesystem-backed tool source.
  `Budget` checks limits before more work starts. `Usage` normalizes and
  adds attempt usage. The caller context carries the optional Session,
  stream dispatch, and review dispatch.

### API use and tests

- [x] Traced DSL and codec authoring through the AI Plugin, route resolution,
  and the shared start, projection, model call, attempt record, and final
  reply Actions. Checked stock and custom root Flow inputs. Traced generation,
  streaming, embeddings, static and dynamic tools, tool review, model options,
  and portable Session and usage output.
- The focused test tree covers Agent authoring and the Plugin, the client
  contract and mock ReqLLM, context lifecycle and snapshots, budget and
  usage, static and dynamic tools, request policy, tool results, and
  conversation projection. Direct callers include the public examples in
  `examples/15_ai_agents`, `examples/16_guardrail_flows`, and
  `examples/20_context_and_memory_flows`.
- Preflight has no dynamic tool source context. A schema-valid unknown tool
  name passed preflight in a probe and failed at live tool selection.
  The selection check needs the combined tool catalogue from the host.
  String keys for closed Flow fields such as `input` and `limits` were
  rejected in both preflight and execution. The open `options` map differs.

### Defects

| Severity | Issue | Verified result |
| --- | --- | --- |
| P2 | [#497](https://github.com/agentjido/jido/issues/497) | Preflight kept Agent instructions. A custom root Flow received the request override. |
| P2 | [#498](https://github.com/agentjido/jido/issues/498) | The inference client received one raw option tool while the effective context Toolset was empty. The result also occurred with disabled tools. |
| P3 | [#499](https://github.com/agentjido/jido/issues/499) | A string model-option key passed preflight and failed with `invalid_req_llm_options` before the client call. |
| P3 | [#500](https://github.com/agentjido/jido/issues/500) | Disabling tools with an inherited review name returned `review_tool_not_visible`. |
| P3 | [#501](https://github.com/agentjido/jido/issues/501) | Nil entries and improper lists raised in Toolset validation. |
| P3 | [#502](https://github.com/agentjido/jido/issues/502) | Two attempts kept total tokens and total cost. The aggregate lost tool-use input tokens and reasoning cost. |

### Code quality and behavior-preserving changes

- [x] Checked duplicate declarations, repeated validation and history work,
  branching, and shared contracts. Three bounded changes have a clear
  improvement and acceptance checks.

| Severity | Issue | Change and behavior to preserve |
| --- | --- | --- |
| P3 | [#504](https://github.com/agentjido/jido/issues/504) | Extract stable correlation data once per model attempt. Keep event data and order, guard withholding, request IDs, and cache keys. |
| P3 | [#506](https://github.com/agentjido/jido/issues/506) | Build complete exchanges in linear list time. Keep message order, tool matching, eligibility decisions, limits, and breakpoint. |
| P3 | [#508](https://github.com/agentjido/jido/issues/508) | Derive the callback set from the behaviour. Keep selection precedence, fallback, validation errors, and all 22 required callbacks. |

### Elixir and OTP design

- [x] Keep the parent namespace and the existing entry modules. The AI
  Plugin integrates with normal Agent authoring. Flows and Actions run under
  the existing Jido execution and AgentServer lifecycle. The shared Actions
  carry portable request data between steps. ReqLLM owns provider calls and
  stream materialization. Session and Thread own conversation records. Jido
  Telemetry owns correlation and its supervised store.
- Model streaming needs stable correlation fields in the chunk callback.
  Guard capture and approval couple several shared Actions to ReAct. This
  review checked that coupling at the shared boundary. The strategy graph,
  guard design, continuation, and durable replay belong to the separate
  ReAct review.
- Changing the inference callback requirements would change the public
  adapter contract. The cleanup in #508 keeps that surface.

### Verification

- `mix test test/jido/ai` passed all 223 selected tests on Elixir 1.20.4 and
  OTP 29. The suite used offline inference. No live provider tests ran.
- `mix format --check-formatted` and `mix reach.check --arch` passed.
- Local probes exercised the effective-policy and option boundaries through
  `preflight/1` and `cmd/3`, inspected the offline inference options, and
  checked Toolset validation and Usage accumulation directly.
- A fixed two-message projection window took about 26 ms for 512 history
  messages and 455 ms for 4,096 messages in a local probe. The repeated list
  copies are visible in source. These timings describe one machine.
- Checked open and closed GitHub issues for overlap. #416 and #421 cover
  replay, persisted attempt size, and Runic limits. #424 covers ReAct guard
  extensions and continuity. The new issues address the parent contracts
  above. The review made no implementation changes.

## Repair coverage

The repair applies Agent policy before a custom root Flow reads its input.
The Agent runner owns the route input callback described in [ADR 0012](../adr/0012-agent-route-input-preparation.md).
The AI Plugin owns the policy. Regression tests compare preflight, direct
commands, and AgentServer with the same request and check standalone Flow
input separately.

Offline provider fixtures check the selected tools, normalized option keys,
and aggregate usage. A stream fixture counts Session decodes at two chunk
counts. A Thread fixture checks complete exchanges and decision order with a
small window and a long history.

## Previous review on 2026-11-13

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
