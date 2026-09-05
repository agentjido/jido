> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Recursive Language Model Simulation

- **ID:** `03_20_recursive_language_model`
- **Status:** archived research profile
- **Complexity level:** 3 - LLM and retrieval
- **Feature group:** llm
- **Test class:** local deterministic

This profile records the earlier domain scope. See the [replacement map](README.md).

## Profile

- **Purpose:** Test bounded recursive execution over input held outside Actor state.
- **User story:** Find failed jobs in a large log corpus and count them by service.
- **Trigger:** An `examples.rlm.run` Signal with a corpus handle, query, optional range, and work limits.
- **Actor state:** Final counts, source ranges, completed call tree, work totals, corpus handle, and completed Turn count.
- **Action:** One Action runs a recursive interpreter. The model selects `read`, `recurse`, or `answer` decisions.
- **External work:** Calls to an immutable corpus store and a scripted model through transient caller context.
- **Directives:** None. All work occurs during the Turn.
- **Commit contract:** A successful request commits once. Failure preserves the prior Actor state. Completed external calls remain in adapter audits. A retry repeats those calls.
- **Source:** [Recursive Language Models](https://arxiv.org/abs/2512.24601).
- **Code:** [Actor](../../../../lib/examples/03_llm/03_10_recursive_analysis/recursive_language_model.ex), [runner](../../../../lib/examples/03_llm/03_10_recursive_analysis/runner.ex), and [tests](../../../../test/examples/03_llm/03_10_recursive_analysis/recursive_language_model_test.exs).

This example tests execution and data boundaries. Model decisions are scripted.
It does not measure model reasoning quality or execute model-generated code.
The single supported query is `:failed_jobs_by_service`.

## Local use

Start `iex -S mix` from the project root, then run:

```elixir
alias Jido.Examples.RecursiveLanguageModel, as: RLM
alias Jido.Examples.RecursiveLanguageModel.{Corpus, Fixtures, ScriptedModel}

{:ok, _instance} = Jido.start_link(name: ExampleJido)
{:ok, store} = Corpus.start_link(%{"logs-v1" => Fixtures.logs(1_000)})
{:ok, model} = ScriptedModel.start_link(chunk_size: 32)
{:ok, actor} = Jido.start_actor(ExampleJido, RLM, exec_opts: [timeout: 10_000])

{:ok, completed} =
  RLM.run(actor, "logs-v1", {ScriptedModel, model}, {Corpus, store})

completed.state.counts
completed.state.usage
completed.state.call_tree
```

The store owns the corpus. A handle must identify an immutable revision.
Ranges use zero-based record offsets and a length. For example,
`range: %{offset: 100, length: 20}` selects records 100 through 119.
With no range, the request selects the complete corpus.

Each call gets a handle, query, range, depth, and parent ID. Internal calls get
child counts. Only leaf calls receive log records. The model audit records the
number of records received without retaining their contents.

The runner requires child ranges to cover the parent exactly. Gaps, overlaps,
duplicate ranges, and recursion over an unchanged range fail. Child order can
change; counts and sorted source ranges remain the same. A reported answer
must agree with the read records or completed child results.

## Limits

Pass overrides in `limits: %{...}` to `RLM.run/5` or `RLM.signal/2`.

| Limit | Default | Meaning |
| --- | ---: | --- |
| `max_depth` | 16 | Root depth is zero. The supported maximum is 64. |
| `max_calls` | 4,095 | Total recursive calls, including the root. |
| `max_steps` | 8,190 | Total model decisions across all calls. |
| `max_bytes` | 8,000,000 | Total encoded record bytes returned by the store. |
| `max_read_records` | 64 | Maximum records in one read and one leaf observation. |

Each limit applies to the complete Turn. Child calls share the remaining
allowance. Byte totals use the sum of `byte_size(:erlang.term_to_binary(record))`
for the records read. They are not token counts or process memory measurements.
The local store checks a prefix byte index before it returns records. A custom
store must enforce the same pre-read allowance contract.

Set `exec_opts: [timeout: milliseconds]` when starting an Actor to limit execution
time. `Server.cancel/1` stops an active Turn. The `timeout:` option to `RLM.run/5`
only limits caller waiting, as with other Actor Server calls.

## Failure controls

The scripted model accepts `chunk_size: positive_integer` and
`order: :forward | :reverse`. To inject a response, use an override key of
`{offset, length, stage}`. Stages are `:start`, `:read`, and `:children`.

```elixir
ScriptedModel.start_link(
  chunk_size: 4,
  overrides: %{{8, 9, :start} => {:error, :provider_timeout}}
)
```

For a 17-record corpus, this response fails after the first two leaf reads.
Tests verify that those effects remain, the prior Actor state remains valid,
and a later request can succeed. Budget errors include `code: :budget_exhausted`,
the limit, requested work, maximum allowance, and completed work totals in the
structured error details.

## Tests and stress command

Run the 26 local tests:

```shell
mix test --only example test/examples/03_llm/03_10_recursive_analysis
```

Run a larger local workload:

```shell
mix run lib/examples/03_llm/03_10_recursive_analysis/stress.exs \
  --records 100000 --leaf 64 --actors 4 --rounds 3
```

| Option | Default | Pressure applied |
| --- | ---: | --- |
| `--records` | 100,000 | Corpus size and total read work. |
| `--leaf` | 64 | Smaller values create more calls and deeper trees. |
| `--actors` | 4 | Concurrent root Actors sharing one corpus store; maximum 64. |
| `--rounds` | 1 | Repeated Turns per Actor. |

The command sets finite work budgets from the fixture size and a 120-second
execution deadline per Turn. It checks the known answer, exact read totals,
leaf bounds, and one commit per round. It prints JSON with timing and work
totals and exits with an error if a check fails.

Recursion within one Actor is sequential. The complete call tree and adapter
audits consume memory as call count grows. Audits accumulate across rounds;
Actor state retains the latest tree. Counts can grow with the number of distinct
services. This example does not impose a total memory limit.

There are no child Actors, restart recovery, or durable intermediate results.
Those are separate requirements in the [integration backlog](../../../../test/integration/README.md#recursive-language-model-simulation).
See the [stress results](../../rlm-results.md) for measured outcomes.
