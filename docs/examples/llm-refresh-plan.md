> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# LLM SDK example refresh

Status: implemented. Ten matching source, test, and profile entries replace the
20 earlier examples. The user added real child Agents to the approved sequence.
All 66 LLM tests pass. See [current results](llm-results.md).

The Workflow refactor is committed as `357b22a`:
`refactor(examples): prove workflow SDK contracts`. Its nine fixtures passed
all 33 tests again before the commit. That commit includes beta.4 Flow formatter
support. It excludes the separate Thread migration and RLM implementation.

The pre-refactor LLM inventory had 20 examples, including the local RLM
example. Historical review command:

```shell
mix test --only example test/examples/03_llm --seed 0
```

Result: **64 passed, one skipped**. RLM accounts for 26 passing tests. The
skipped Deep Research case states that the full research loop is not implemented.

## Assessment

Basic establishes the Agent boundary. Workflow establishes execution structure.
LLM should show how model output enters that structure and how the application
controls its use.

Many current LLM examples call an adapter, check an application result, and
commit once. Company reports, literature reviews, marketing plans, stock
reports, and image-region answers mainly change the result fields and policy.
Those policies can be useful without requiring separate SDK integration fixtures.

The current tests use real Agents and Servers, so they are local integration
tests. Their strength varies. Several tests check only final values. For
example, Model Fallback's authentication test checks the error and revision,
but its fixed backup adapter does not record whether it was called.
Conversational RAG's resolver returns a preset query and ignores the supplied
history. That proves result assembly, not use of prior context.

ReAct is stronger: it records model and tool effects, exercises continuation,
rejects malformed decisions, enforces a model-step policy, and tests cancellation.
RLM adds explicit caller context, shared application budgets, independent result
checks, real worker termination, and queued-request isolation. Preserve this
evidence when reducing the number of folders.

The LLM examples define application model and tool adapters. This checkout has
no common SDK model client used by the batch. Do not describe fallback, evidence
grading, message retention, or recursive byte budgets as built-in Jido policy.
Jido supplies execution, schemas, context, errors, serialization, cancellation,
and commits. The examples must identify the application decisions separately.

## Implemented sequence

Use **nine focused fixtures and one larger final example**. Each has one main
additional capability. Reuse earlier contracts without repeating their complete
test matrix. This is a learning order, not a requirement that every later
example include all earlier features.

| Current folder | Additional capability | Jido integration to prove | Main sources |
| --- | --- | --- | --- |
| `03_01_model_response` | One model response crosses a typed application boundary | A real Action receives a transient client, validates input/output, and commits only the selected result fields | Starter Chatbot, Model Fallback |
| `03_02_conversation_history` | History carries across Turns | The next model call receives committed history; duplicate input and failed work preserve the correct state; restored history works with a fresh client | Starter Chatbot, Conversational RAG |
| `03_03_tool_call` | Model data selects one approved tool | A name resolves through an application allowlist to a typed Jido Action; invalid arguments or denied policy stop before the tool effect | Single-Tool Agent, Coding Assistant, Data Analyst |
| `03_04_tool_loop` | Tool results drive the next model decision | Flow Dispatch and executable continuation carry context and history through repeated steps within one commit and one execution deadline | ReAct Agent, Plan and Execute |
| `03_05_parallel_tools` | One model decision requests concurrent tools | Map runs real tool Actions under the SDK concurrency limit; call IDs and ordered results survive different completion orders | New focused composition of tool selection and Workflow Ordered Batch |
| `03_06_grounded_answer` | An answer must refer to supplied evidence | Retrieval, model generation, and application citation validation compose through a Flow; a bad final citation prevents the complete commit | Document Q&A and the report/RAG variants |
| `03_07_output_repair` | Invalid output receives bounded correction feedback | Iterate carries explicit attempt data and validation feedback; only a valid terminal result reaches the Agent commit | Self-Evaluation Loop, Agentic RAG |
| `03_08_context_compaction` | Stored history is replaced by a smaller model context | The application selects a prefix, validates the summary, and commits it with the retained suffix; queued new messages use the resulting state | Conversation Summarization |
| `03_09_subagent_delegation` | A model selects an approved child specialist | Portable SpawnAgent and Work Directives, explicit child caller context, result correlation, failure, and child cleanup across separate Turns | New child-Agent example |
| `03_10_recursive_analysis` | Large external context is processed through a bounded call tree | One Action runs the application RLM runner under Agent context, deadline, cancellation, and terminal commit contracts | Recursive Language Model |

Model fallback belongs in Model Response as an error-path case. Workflow Choice
already proves branch selection. A second standalone fallback fixture would
add little SDK evidence. Tool permission checks belong with Tool Call. A bounded
precomputed plan uses Parallel Tools at concurrency one. It shares complete
plan admission with the concurrent case.

Parallel Tools is the main new gap. The current LLM examples do not prove
parallel model-selected calls and result correlation. Workflow proves ordered
Map execution; the LLM fixture adds validation of generated call IDs, names,
arguments, and the transcript supplied to the next model call.

## Integration acceptance cases

### 03_01 Model Response

- A successful call receives the exact request and transient client context.
  Only validated response data enters Agent state and persistence.
- Invalid request data reaches no provider. Malformed provider output preserves
  a non-default prior commit.
- As an explicit application policy, a transient primary error can select a
  compatible backup. Record both attempts. Authentication failure makes zero
  backup calls. A malformed backup response does not commit.
- An actual execution deadline terminates a blocked provider worker. Keep this
  distinct from the timeout for waiting on `Server.call`.

### 03_02 Conversation History

- Two Turns record the actual model inputs and prove stable message order.
- A repeated message ID makes no additional provider call. Define explicitly
  whether the application rejects it or accepts an unchanged result; do not
  confuse duplicate suppression with the SDK commit-revision contract.
- A model failure preserves existing messages. Restore persisted history and
  run the next Turn with a fresh caller-context client.

### 03_03 Tool Call

- A model-selected approved name invokes one typed Jido Action. Its result is
  given to the final model call with the same call ID.
- Unknown names, invalid arguments, and denied operations make zero tool calls.
  Model output cannot name an arbitrary module or bypass the allowlist.
- A tool failure or later answer-validation failure prevents the state commit.
  A recorded tool effect remains visible after a later failure.
- Keep domain rules such as allowed repository paths or table operations as
  small policy cases. An in-memory repository transaction does not prove SDK
  rollback or a real command sandbox.

### 03_04 Tool Loop

- Multiple model/tool rounds produce the exact ordered transcript and one
  terminal commit. A held intermediate step exposes the prior Agent snapshot.
- Preserve the current ReAct cases for malformed decisions, unknown tools,
  tool failure, late model failure, and completed external effects.
- Test the exact application model-step bound and the SDK continuation limit
  as distinct controls. Context survives each continuation.
- Cancellation stops the active worker. A later request succeeds with its own
  context. The fixed-plan variant is covered by 05 at concurrency one, with
  complete plan admission before any tool runs.

### 03_05 Parallel Tools

- Require two tool workers to enter before either is released. Also test the
  serial limit. Return replies in reverse completion order and verify the exact
  call-ID/result sequence received by the model.
- Reject duplicate call IDs, unknown names, and invalid arguments before fan-out.
  Define whether plan admission is all-or-nothing; do not let invalid plans
  partially execute by accident.
- Cover an empty tool list, a collected item error, and cancellation of all
  active workers. Follow the final upstream Map error/fail-fast contracts.
- This uses the same Map implementation as Workflow; do not build a second
  application scheduler or repeat the entire Map/Reduce test matrix.

### 03_06 Grounded Answer

- Record the retrieval request and the exact evidence given to the model.
- No evidence reaches no generation step. An invented citation or mismatched
  document revision rejects the result while preserving the previous commit.
- A conversation variant checks the actual query resolver's history input.
  An allowed web fallback is a policy case and must record whether it ran.
- Region/page references can be a small data variant. Matching a citation ID
  proves provenance checks, not factual correctness or image understanding.

### 03_07 Output Repair

- Valid first output makes no repair call. Invalid output sends specific
  validation feedback into the next recorded model request.
- The last permitted repair can succeed. Exhaustion makes exactly the allowed
  number of calls and leaves prior Agent state unchanged.
- Keep expected validation failures as explicit attempt data, then validate the
  terminal result. Do not assume that an uncaptured Action error resumes a Flow.
- Schema validity is the acceptance target. A scripted quality score is not
  evidence that real model output improved. Keep that scoring policy separate.

### 03_08 Context Compaction

- Read messages from committed Agent state. The current summarizer accepts a
  caller-supplied entry list; the refreshed fixture must prove stored-history use.
- Validate the summary, retain the recent suffix, and prove that the next model
  call receives the selected summary and suffix without duplicate messages.
- Hold compaction while a new message is queued. Release it and prove that the
  message is appended to the new committed state rather than lost.
- Fact loss, malformed summary, or an exceeded application context limit leaves
  prior history unchanged. Name the measured limit: message count or bytes do
  not prove a model-specific token limit.

### 03_09 Subagent Delegation

- The planner selects one approved specialist role. The parent commits pending
  state, emits portable Directives, and starts a real child Agent.
- A process-free Plugin passes the work Signal and client context to the child.
  The child's successful model Turn emits a result Signal to its parent.
- Exact request/tag correlation rejects stale and duplicate results. A repeated
  request ID makes no additional planner or specialist call.
- Invalid selection starts no child. Child model failure, process loss, and the
  child's separate execution deadline produce a failed result and cleanup.
  A later request can succeed. Prior completed results remain in Agent state.
- This is one child per request and several Agent commits. It does not claim
  concurrent subagent trees, authenticated replies, durable recovery, or a
  transaction across Agents. Failure during child startup remains outside scope.

### 03_10 Recursive Analysis

- Preserve the current RLM regression matrix and stress runner. Do not reduce
  its 26 tests solely to make its count resemble the smaller examples.
- Preserve exact/shared depth, call, step, byte, and read-size limits; malformed
  partitions; false leaf/parent results; independent expected counts; late
  failure; queued context isolation; cancellation; and execution deadlines.
- Keep corpus data external and persist only selected result/trace data. The
  current trace grows with call count; do not claim a total memory bound.
- The runner owns recursion and work accounting. Jido owns the outer execution
  lifecycle. Sequential recursion inside one Action is not nested child-Agent
  execution, a native Flow recursion primitive, or durable recovery.

## Disposition of every current example

Numbers in the destination column refer to the implemented sequence above.

| Current example | What its code/tests currently show | Disposition |
| --- | --- | --- |
| [03_01_agentic_rag](archive/llm/03_01_agentic_rag.md) | Custom retrieve/grade/rewrite recursion; one rewrite-success test | Use the bounded-feedback pattern in 07 and evidence cases in 06; remove the separate SDK fixture |
| [03_02_coding_assistant](archive/llm/03_02_coding_assistant.md) | Allowed paths/commands and a fake atomic repository transaction | Move permission and late-effect cases to 03; keep coding details in the research archive |
| [03_03_company_research](archive/llm/03_03_company_research.md) | Citation membership and conflict grouping over supplied records | Fold evidence checks into 06; archive the report-specific scenario |
| [03_04_conversation_summarization](archive/llm/03_04_conversation_summarization.md) | Required-fact validation and compacted entry selection | Refine into 08, using actual committed history and queued Turns |
| [03_05_conversational_rag_memory](archive/llm/03_05_conversational_rag_memory.md) | History/result assembly with fixed resolver and retrieval replies | Feed 02 and a recorded-context variant of 06 |
| [03_06_data_analyst](archive/llm/03_06_data_analyst.md) | Allowed table operations and deterministic arithmetic | Use an allowed-tool policy case in 03; keep arithmetic outside SDK integration coverage |
| [03_07_deep_research](archive/llm/03_07_deep_research.md) | Validation of a finished replay result; full research loop is skipped | Archive the unfinished research profile/backlog. Preserve useful ledger checks in 06, without claiming that the missing loop is implemented |
| [03_08_document_question_answering](archive/llm/03_08_document_question_answering.md) | Real Retrieve/Generate/Commit Flow with citation failure cases | Main source for 06 |
| [03_09_literature_review](archive/llm/03_09_literature_review.md) | DOI deduplication and citation membership | Fold citation identity into 06; archive literature-specific output |
| [03_10_marketing_strategy](archive/llm/03_10_marketing_strategy.md) | Allocation totals and evidence-ID checks | Use bounded/validated output ideas in 07 and evidence checks in 06; archive the business scenario |
| [03_11_model_fallback](archive/llm/03_11_model_fallback.md) | Explicit transient-error policy and backup output checks | Merge into 01; add actual provider-attempt observations |
| [03_12_multimodal_document_agent](archive/llm/03_12_multimodal_document_agent.md) | Page/region/digest equality against supplied metadata | Small evidence variant in 06; no claim of actual image-model coverage |
| [03_13_plan_and_execute](archive/llm/03_13_plan_and_execute.md) | Bounded allowlisted plan and ordinary serial adapter calls | Fixed-plan case in 05 at concurrency one, with tool contracts from 03 |
| [03_14_rag_web_fallback](archive/llm/03_14_rag_web_fallback.md) | Local evidence grading, explicit web permission, citation checks | Policy variant in 06; no separate routing fixture |
| [03_15_react_agent](archive/llm/03_15_react_agent.md) | Real Flow Dispatch/continuation, observable effects, failures, limits, cancellation | Main source for 04; preserve its strong runtime checks |
| [03_16_self_evaluation_loop](archive/llm/03_16_self_evaluation_loop.md) | Custom recursion over fixed drafts/scores; best-draft selection | Refine into 07 with objective validation feedback; retain scoring policy only as domain material |
| [03_17_single_tool_agent](archive/llm/03_17_single_tool_agent.md) | One selected adapter call and final answer; unknown-name rejection | Main source for 03; strengthen typed Action execution and zero-effect assertions |
| [03_18_starter_chatbot](archive/llm/03_18_starter_chatbot.md) | Agent-owned history across Turns and duplicate suppression | Split the minimal model boundary into 01 and history behavior into 02 |
| [03_19_stock_analysis](archive/llm/03_19_stock_analysis.md) | Dated input checks, arithmetic, and fixed commentary | Archive the report scenario; retain revision/metadata cases where useful in 06 |
| [03_20_recursive_language_model](profiles/03_llm/03_10_recursive_analysis.md) | Substantial local recursive execution and stress evidence | Retain as 10 with its tests and scope limits |

## Refactor rules

Use matching folders in `lib/examples/03_llm`, `test/examples/03_llm`, and the
profile directory. Keep source attribution and retired domain requirements in
an archive with an explicit old-to-new mapping.

Use real Agents, Signals, Actions, Flows, Exec, schemas, and Server commits.
Script only external model/tool/retrieval responses. Record all attempts before
any deduplication. Use barriers and monitored workers for execution assertions.

Put model, tool, and retriever clients in caller context. Several current
helpers, including ReAct, place clients in Signal data and copy them through
Flow results. RLM already demonstrates the preferred transient context path.
Signals should contain application request values and portable identifiers.

Use a small example-owned adapter/recorder contract where repetition warrants
it. Do not introduce a new core LLM abstraction as part of this example cleanup.
Use Zoi for request, tool-argument, attempt, and terminal-result contracts.

Keep every claimed SDK obligation enabled. Move Deep Research's unimplemented
profile requirement to the backlog rather than carrying a permanently skipped
test in the refreshed SDK batch. This changes the batch's claim, not the status
of the unfinished research feature.

Keep live provider conformance and model-quality evaluations separate. The
local suite proves execution and application boundaries; fixed replies do not
prove provider compatibility, factual accuracy, or model quality.

Use the agreed upstream Map and capture contracts when available. Track their
adoption through the existing Workflow issues. Do not duplicate those fixes in
LLM example code or treat current message-only Map errors as the desired API.
