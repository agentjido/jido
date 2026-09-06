> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# LLM SDK integration results

The LLM batch now has ten source folders, ten matching test folders, and ten
current profiles. The learning order adds one capability at a time. All 66
LLM tests pass with no skips. Each numbered folder also passes on its own.

## Current sequence

| Fixture | Added capability | Passing tests |
| --- | --- | ---: |
| [Model Response](profiles/03_llm/03_01_model_response.md) | One typed response, transient client context, selected persisted fields, and explicit fallback policy. | 4 |
| [Conversation History](profiles/03_llm/03_02_conversation_history.md) | Actual history across Turns, duplicate rejection, and restore with a fresh client. | 2 |
| [Tool Call](profiles/03_llm/03_03_tool_call.md) | An approved name resolves to a typed Action; invalid input stops before tool effects. | 4 |
| [Tool Loop](profiles/03_llm/03_04_tool_loop.md) | Flow Dispatch and continuation carry model/tool rounds to one terminal commit. | 11 |
| [Parallel Tools](profiles/03_llm/03_05_parallel_tools.md) | Validate a complete tool plan, run concurrent Actions with Map, and retain call-ID order. | 5 |
| [Grounded Answer](profiles/03_llm/03_06_grounded_answer.md) | Retrieve evidence, generate an answer, and validate citation identity, revision, and page before commit. | 3 |
| [Output Repair](profiles/03_llm/03_07_output_repair.md) | Flow Iterate carries validation feedback through at most three model attempts. | 3 |
| [Context Compaction](profiles/03_llm/03_08_context_compaction.md) | Compact committed history and retain recent and queued messages under an explicit byte limit. | 2 |
| [Subagent Delegation](profiles/03_llm/03_09_subagent_delegation.md) | Spawn a real child Agent, transfer client context explicitly, and correlate result and failure Signals. | 6 |
| [Recursive Analysis](profiles/03_llm/03_10_recursive_analysis.md) | Run the bounded application recursion tree under one Agent execution lifecycle. | 26 |

## SDK and application responsibilities

Jido supplies Signal routing, Action and Flow execution, caller context,
validation boundaries, serialization, execution limits, cancellation, child
lifecycle, Directive dispatch, and Agent commits. The examples supply model
adapters, approved tool names, duplicate rules, citation checks, fallback
policy, summary checks, and recursive work accounting.

The tests record actual provider inputs and every attempted call. Barriers
hold real execution workers to prove order, overlap, commit visibility, and
termination. Tests cover failure after a prior successful commit and show
that completed external calls remain visible after a later failure. Client
handles enter through caller context and do not enter portable request data.

The finite precomputed plan case is in Parallel Tools at concurrency one. It
uses the same complete plan admission as concurrent execution. This avoids a
second plan runner in Tool Loop. ReAct keeps all nine earlier cases and adds
two tests for intermediate state, exact transcripts, and the SDK continuation
limit. Cancellation also tests the next request's fresh context.

## Real subagents

[Subagent Delegation](profiles/03_llm/03_09_subagent_delegation.md) starts a real
child Agent for one approved model-selected role. A parent pending commit
precedes child execution. A portable Work Directive uses a process-free Plugin
to send the work Signal with explicit child caller context. The child performs
its own model Turn and emits a correlated result Signal to the parent.

Six tests prove portable Directives, separate parent/child state, stale and
duplicate reply handling, selection rejection, model failure, child process
loss, execution deadline, cleanup, and a later successful request. Each request
uses one child. This does not claim concurrent subagent trees, authenticated
replies, child-start failure recovery, durable recovery, or a transaction
across Agents. The initial call returns pending state. A later Turn commits
completion or failure.

Recursive Analysis remains separate: its application runner recurses inside
one Action. All 26 tests and the stress runner were retained. The moved source
is unchanged. Only its test tag and paths changed.

## Validation

```shell
mix test --include integration test/examples/03_llm --seed 0
mix test --include example --seed 0
mix compile --warnings-as-errors
mix format --check-formatted
mix credo suggest 'examples/03_llm/*.{ex,exs}' \
  'examples/03_llm/**/*.{ex,exs}' 'test/examples/03_llm/**/*.exs' \
  'test/support/llm_sdk_case.ex' --strict
mix run -e 'Mix.Tasks.Docs.run([])'
git diff --check
```

- LLM: **66 passed**, no skips.
- Earlier wider regression: **770 passed, 35 skipped, 12 excluded**. The skips and
  exclusions are outside this LLM batch. Existing invalid-input type warnings
  appear in `test/jido/id_test.exs`.
- Each of the ten numbered LLM folders passes independently.
- Compilation, formatting, focused strict Credo, ExDoc, diff whitespace, and
  local example-document links pass.

See the [workspace checkpoint](checkpoint.md) for the later full run with all
integration tests enabled and its two existing group failures.

## Limits and retained research

Fixed replies prove local integration, not factual accuracy, model quality,
live provider compatibility, image understanding, or model token limits.
Compaction checks required strings and UTF-8 content bytes. RLM budgets count
application work; they do not bound total memory.

Map collect mode still uses the beta.4 message-only error contract. The
application restores call IDs from the admitted plan's stable positions.
Structured error adoption remains tracked by
[v3 issue 18](https://github.com/mikehostetler/jido_v3/issues/18).

The [archive](archive/llm/README.md) retains all 20 earlier profiles, source
attribution, and a replacement map. The full Deep Research loop remains
unimplemented. Its permanently skipped test was removed with the old fixture;
that does not mark the research requirement complete. The LLM fixture refactor
does not change Agent execution or upstream Flow code. The accompanying
[history migration](agent-history.md) removes the Thread Plugin.
