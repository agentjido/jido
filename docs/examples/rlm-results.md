> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# Recursive Language Model stress results

Run date: **2026-09-03**. Runtime: **Elixir 1.20.3, OTP 29**.

The [RLM example](profiles/03_llm/03_10_recursive_analysis.md) uses a
scripted model and an immutable local corpus store. It tests real Agent
construction, Signal routing, Action execution, cancellation, and Server
commits. No network or model credentials are required.

## Verification

| Check | Result |
| --- | --- |
| RLM suite | 26 passed |
| Historical LLM and Basic groups, before the LLM refresh | 79 passed, one unfinished Deep Research test skipped |
| Compilation with warnings as errors | Passed |
| Format check for new source and tests | Passed |
| Strict Credo check for the eight new source, script, and test files | Passed |

The repository-wide Credo run reports existing issues outside this example.
The focused check used explicit file globs. These results do not claim that the
full repository quality gate passes or that OTP 27 was tested.

Current commands for the moved suite (the run above used the earlier path):

```shell
mix test --include integration test/examples/03_llm/03_10_recursive_analysis
mix test --include integration test/examples/03_llm test/examples/01_basic
mix compile --warnings-as-errors
mix credo suggest 'examples/03_llm/03_10_recursive_analysis/*.{ex,exs}' \
  'test/examples/03_llm/03_10_recursive_analysis/*.exs' --strict
```

## Tested contracts

- Direct evaluation returns an immutable candidate. Server execution returns
  the same state and commits once.
- Empty inputs, inputs without failures, irregular partitions, and reverse
  traversal produce the expected counts and complete source coverage.
- A request for 17 records within a 4,096-record corpus reads only that range.
- Depth, recursive calls, model steps, bytes, and read size have shared limits.
  Exact limits succeed. Excess work fails before the next disallowed operation.
- A skewed tree reaches depth 64. Depth 65 fails without a new commit.
- Gaps, overlaps, duplicate ranges, and recursion over an unchanged range fail.
- False leaf and parent counts, malformed replies, invalid records, false byte
  totals, missing context, stopped stores, and provider exceptions fail.
- A late failure preserves the prior committed answer. Earlier adapter calls
  remain visible. A later retry can complete.
- Cancellation and an execution deadline terminate blocked model work after a
  completed read. Queued work retains its own caller context.
- A result with 820 distinct services is assembled from leaves of four records.
- Four concurrent Agents each process 16,384 records in 8,191 recursive calls.
  Each Agent commits once. No leaf receives more than four records.

## Larger repeated run

```shell
mix run examples/03_llm/03_10_recursive_analysis/stress.exs \
  --records 100000 --leaf 64 --agents 4 --rounds 3
```

All **12 executions passed**. Four root Agents shared one corpus store. Each
Agent had its own scripted model and completed three Turns.

| Measure | Per execution | Complete run |
| --- | ---: | ---: |
| Records read | 100,000 | 1,200,000 |
| Encoded record bytes read | 13,768,890 | 165,226,680 |
| Recursive calls, including root | 4,095 | 49,140 |
| Model decisions | 8,190 | 98,280 |
| Maximum depth | 11 | 11 |
| Largest leaf read | 49 records | 49 records |
| State commits | 1 | 12 |

Every result contained 20,000 failed jobs. `service-0` had 2,858 failures; each
of the other six services had 2,857. Every round matched the independent fixture
answer and exact work totals.

The measured run took **3,450.1 ms**. Individual concurrent executions took
1,095.2 through 1,160.7 ms. Timing excludes compilation, initial fixture and
corpus construction, and final instance shutdown. It includes Agent startup
and execution. Other verification ran on the same machine, so this is a local
observation, not a performance guarantee.

## Scope and remaining pressure

Recursion is sequential inside each Agent Turn. Concurrent root Agents test
shared store contention; this does not test concurrent child Agents.
The corpus stays outside Agent state, but completed call trees and adapter
audits grow with call count. Audits accumulate across rounds. There is no total
memory limit or token budget.

The model uses deterministic rules for one aggregation task. The example does
not execute generated code, measure model quality, persist intermediate work,
or recover a recursion tree after a restart. Child Agent lifecycle and recovery
remain in the [integration backlog](../../examples/08_applications/README.md#recursive-language-model-simulation).

The LLM refresh retains all 26 RLM tests in `03_10_recursive_analysis`. The
[current LLM results](llm-results.md) cover the new ten-example sequence. The
unfinished Deep Research profile is now in the research archive.
