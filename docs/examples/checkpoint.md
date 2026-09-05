> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# Workspace checkpoint — 2026-09-04

This checkpoint records the Agent DSL, inline Step adoption, example cleanup,
and persistence fix. The next work starts with the remaining test failures and
runtime recovery contracts below. The full suite is not yet green.

Later on the same date, the [research capability review](research-capabilities.md)
replaced the active vendor/application backlog with 12 Jido capability targets.
It also measured remote PID commands and the missing remote-child placement
path on two real Erlang nodes. The commit and validation tables below retain
the earlier checkpoint results.

The subsequent [DIST-01 implementation](dist-01-results.md) resolves remote
child placement through the agreed core `SpawnAgent.node` field.

The current tree has since promoted seven solved research capabilities into
Runtime and Multi-agent. It removed the 48 application and adapter fixtures
from the runnable tree and kept them in Git history at `bd05a32`. The
[beta.6 adoption](inline-actions-expressions-results.md) now uses portable
inline Actions and `Jido.Expr`. The tables below retain the earlier checkpoint.

## Commits

| Commit | Work |
| --- | --- |
| `03d4240` | Runtime error cleanup and Plugin admission/startup regression tests |
| `ed58b5d` | Atomic persistence writes, expected revision checks, and adapter/Server tests |
| `7dda672` | Inline Steps, generated command cleanup, feature examples, `99_research`, and gap reports |

These follow `18ffae3`, which extended the Spark Agent DSL across the examples.
The earlier DSL and LLM work remains in `f338208` and `90bd3c6`.

## Completed work

- Agent definitions support Spark, map, keyword, Builder, and JSON forms.
  Routes generate command and Signal helpers. Commands use descriptive names.
- At this checkpoint, Basic operations used Actions and Workflow Flows used
  short inline Step bodies. `jido_action` was pinned to Hex `3.0.0-beta.5`.
- Runtime has eight feature fixtures. Multi-agent has four. Each shows an
  additional SDK feature with live runtime checks.
- The 48 wider experiments live under `lib/examples/99_research` and
  `test/examples/99_research`. All 54 original Runtime and Multi-agent profiles
  remain in the documentation archive.
- Persistence rejects stale writes through atomic compare-and-swap. A rejected
  Server commit preserves live state and sends no Directives. The former
  Runtime persistence skip is enabled.
- The six earlier Dialyzer findings are fixed without suppressions.

## Current example results

| Group | Fixtures | Passing tests | Skips |
| --- | ---: | ---: | ---: |
| Basic | 5 | 22 | 0 |
| Workflow | 9 | 35 | 0 |
| LLM | 10 | 66 | 0 |
| Runtime | 8 | 29 | 0 |
| Multi-agent | 4 | 18 | 0 |
| `99_research` | 48 | 69 | 34 |

The five main groups have 36 fixtures and 170 passing tests. Research skips
remain visible; they are not proof that the SDK cannot support those scenarios.
See the [catalog](catalog.md) and [research map](runtime-multi-agent-research.md).

## Validation

| Check | Result |
| --- | --- |
| Fresh checkpoint run: five main example groups plus persistence, instance, Plugin, and startup tests | 239 passed; no skips |
| Fresh `mix quality` | Passed; no application compile warnings or Dialyzer findings |
| Full suite, seed 0, default concurrency, from the persistence validation | 859 of 862 passed; 34 research skips; 3 failures |
| Full suite, seed 0, `--max-cases 1`, from the persistence validation | 860 of 862 passed; 34 research skips; 2 failures |
| Local Redis 8.6.2 checks from the persistence validation | 2 passed; binary values, TTL, and concurrent writers |
| Documentation build and local Markdown links | Passed |
| Formatting and Git whitespace checks | Passed |

The fresh focused command was:

```shell
mix test --include integration \
  test/examples/01_basic test/examples/02_workflow test/examples/03_llm \
  test/examples/04_runtime test/examples/05_multi_agent \
  test/jido/persistence_test.exs test/jido/persistence \
  test/jido/instance_test.exs test/jido/agent/plugin_test.exs \
  test/jido/agent/startup_test.exs --seed 0
mix quality
```

The full suite still emits five existing test compiler warnings for deliberate
invalid inputs and redundant assertions. These are separate from application
compilation, which passes with warnings treated as errors. Tests ran on Elixir
1.20.3 and OTP 29. Release QA still needs Elixir 1.18 and OTP 27+.
No live model provider, Redis failover, or multi-node cluster test ran.

## Compatibility notes

Custom persistence adapters must implement `compare_and_swap/4`. Changed
checkpoint state requires a greater revision; equal revisions permit only an
identical record. File persistence requires one BEAM owner for its directory.
The [persistence report](persistence-write-results.md) defines the API and limits.

Earlier history changes removed `Jido.Plugin.Thread` and
`Jido.Plugin.Thread.Set`. Applications that use those modules must follow the
[Agent history migration guide](agent-history.md). `Jido.Thread` remains an
optional data value.

## Next work

1. **QA-GROUPS:** Fix the Fixed Group and Elastic Group integration fixtures.
   Their Bus lookup scope differs from Agent dispatch scope. Define how a
   restored worker handles interrupted work before changing restart assertions.
   Current failures are at the Fixed Group replay wait and Elastic Group
   post-crash result wait.
2. **QA-CONTEXT:** Check the 100 ms delivery timeout in `ServerContextTest`
   under concurrent test load. It passes in focused and serial runs and does
   not use persistence. Preserve its context and delivery assertions.
3. **SDK-SCHEDULE:** Define durable occurrence identity, acknowledgement,
   retry, and missed-window policy. Add controlled clock and crash tests.
4. **APP-RECOVERY:** Define whether managed jobs are abandoned, retried, or
   resumed after runtime loss. Persist intent and test external idempotency.

The [gap register](runtime-multi-agent-gaps.md) contains evidence, ownership,
and the next experiment for each item. The
[Runtime and Multi-agent report](runtime-multi-agent-results.md) preserves the
reorganization results. The [inline Step report](inline-step-results.md) and
[interface review](example-interface-results.md) record the earlier syntax work.
