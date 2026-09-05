> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# Example interface review

> The Runtime and Multi-agent catalog was reorganized on 2026-09-04. See the
> [current feature review](runtime-multi-agent-results.md) for current paths, test
> totals, and gap ownership. Results below describe the earlier review.

Date: **2026-09-04**. Scope: all **78 examples and 79 Agent declarations**.
The extra Agent is the LLM specialist child.

## Changes

Plain Signal and Server-call wrappers now use nested `define` declarations.
Tests call the generated commands or Signal constructors. Generic Agent
`run` commands and `signal` aliases are removed. Action `run/2` callbacks remain.

Representative command names:

| Example | Command |
| --- | --- |
| Sequential Flow | `double_value` |
| Effectful Steps | `fetch_record` |
| Parallel Join | `fetch_pair` |
| Ordered Batch | `convert_all`, `collect_results` |
| Nested Flow | `draft_and_review` |
| Executable Continuation | `add_repeatedly` |
| Approval Workflow | `search_flights`, `select_fare`, `approve_booking` |
| Dynamic Tool Catalog | `invoke_tool` |
| Browser Agent | `browse` |
| Fixed Group | `assign_tasks` |
| Codebase Review Tree | `review_codebase` |
| Recursive Analysis | `analyze` |

Basic uses `increment` or `set_count` in place of generic `change` helpers.
Purpose Loop, Coordinator, Voice Assistant, Adaptive Swarm, and Persistent
Campaign expose one command for each fixed event type. They no longer require
callers to supply strings that form a Signal type.

Small typed inputs use positional arguments. Wider requests use `input: %{...}`.
Defaults belong to routes or executable schemas. Optional list inputs stay in
named input maps so they cannot be confused with command options.

```elixir
{:ok, agent} = Jido.Examples.ParallelJoin.fetch_pair(server, 3)
{:ok, signal} = Jido.Examples.ParallelJoin.fetch_pair_signal(3)
signal = Jido.Examples.ParallelJoin.fetch_pair_signal!(3, :left)

{:ok, agent} =
  Jido.Examples.ApprovalWorkflow.search_flights(server,
    input: %{constraints: constraints},
    context: %{search: search_adapter},
    timeout: 5_000
  )
```

Constructors package input. Defaults and executable validation apply during
command execution. The Parallel Join Flow now declares integer input and a
failure selector with default `:none`. Its new test checks the generated tagged
constructor, live command, default value, transient context, rejection before
branch work, and preservation of committed state.

The Iteration and Nested Flow examples keep explicit input maps. Their tests
still reach the intended iteration-state and child-Flow validation boundaries.
Basic still uses Actions for single operations. Existing inline Steps keep the
five-line selection rule.

## Custom preparation retained

Custom functions remain for work beyond packaging route input:

- Signature and envelope verification occurs before delivery.
- Persistent Counter, Support Email, Slack, and Web Chat preserve stable event IDs.
- ReAct prepares initial continuation state. One `ask` command now accepts
  `max_steps:` and `timeout:` options instead of a separate `ask_with_limit`.
- Recursive Analysis merges application limits and binds transient clients.
- Timer helpers preserve the scheduler source; outbound batch events keep their
  explicit constructor. Raising Signal constructors use `!`.
- Session adapters, recovery, tracing, replay, and background-job setup retain
  their application behaviour.

Existing Signal type strings, source identities, and route targets remain.
The fan-out request's `input.timeout` still limits each worker. The generated
command's `timeout:` option separately limits caller waiting.

## Verification

```shell
mix test --include example --include integration test/examples --seed 0
mix test --include example --include integration --seed 0
mix quality
mix docs --no-open
git diff --check
```

The example suite has **205 passing tests and 35 existing skips**. Basic has 22
passing tests, Workflow has 35, and LLM has 66. No skip or failure exclusion was
added. The full suite has **814 passed, 2 failed, 35 skipped**. The two known
Fixed Group and Elastic Group integration failures remain; see the
[checkpoint](checkpoint.md). These integration fixtures are separate from the
numbered examples with the same names.

`mix quality` passes, including compilation with warnings as errors and
Dialyzer with zero findings. The full test run still emits the five existing
compiler warnings from test files. Documentation generation and diff checks pass.

The full run also exposed a race in the recently added Plugin startup test.
It now waits for registry cleanup with `JidoTest.Eventually`. The startup error
assertion and runtime code are unchanged.
