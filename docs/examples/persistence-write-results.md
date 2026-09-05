> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# Persistence write conflict fix

Date: **2026-09-04**. This approved follow-up closes `SDK-WRITE` from the
[gap register](runtime-multi-agent-gaps.md). The stale-writer test is enabled.
Runtime has **29 passing tests**, and Multi-agent has **18**, with no skips.
The 34 research skips remain under `99_research`.

## Behavior

A stored revision cannot decrease. Different state cannot replace a record at
the same revision. Saving the same record at the same revision is permitted,
so hibernate and normal shutdown can repeat the last durable write.

```elixir
:ok = Jido.Persistence.save_agent(store, newer, revision: 2)
{:error, :conflict} = Jido.Persistence.save_agent(store, older, revision: 1)

# A writer that read revision 2 must still find revision 2 when it saves.
:ok = Jido.Persistence.save_agent(store, next,
  revision: 3, expected_revision: 2)
```

`expected_revision: 0` also accepts an absent record for the first commit.
A positive expected revision requires an existing record with that revision.
Direct saves without `expected_revision` accept any older stored revision.
Direct saves still default to revision zero; changed state requires the caller
to supply a greater revision. Invalid or corrupt records are not overwritten.

Every Server write supplies its current `state_version` as the expected
revision. A rejected commit returns
`{:error, {:persistence_failed, :conflict}}`. Live state and its revision remain
unchanged, and its Directives do not run. The configured error policy decides
whether the Server continues or stops. There is no automatic command retry or
reload. External work performed by an Action before commit is not undone.
A stale hibernate returns `{:error, :conflict}` and keeps the Server alive.
A stale normal shutdown reports the error and preserves the newer record.

## Adapter contract and migration

[Persistence](../../lib/jido/persistence.ex) reads and validates the current
record, then supplies its exact bytes to the new
[`compare_and_swap/4` callback](../../lib/jido/persistence/adapter.ex).
The adapter must compare and write as one atomic operation. A change between
the read and write returns `{:error, :conflict}`. An absent record uses the
`:not_found` expectation. Adapters continue to store bytes without decoding
Agent checkpoints.

Custom adapters must implement this callback. Configuration rejects adapters
that lack it with `{:error, {:invalid_persistence_adapter, adapter}}`.
There is no fallback to an unconditional write. Existing encoded records do
not need migration. Raw `put/3` and `delete/2` remain unconditional storage
operations and must not be used to bypass checkpoint revision checks.

| Adapter | Atomic write mechanism | Scope |
| --- | --- | --- |
| [ETS](../../lib/jido/persistence/ets.ex) | `insert_new` or `select_replace` | One ETS table within a BEAM lifetime |
| [File](../../lib/jido/persistence/file.ex) | Per-record lock around comparison and rename; writes and deletes share the lock | One BEAM owns the directory; no concurrent OS-process or other BEAM writers, and no alternate symbolic-link paths |
| [Redis](../../lib/jido/persistence/redis.ex) | One Lua `EVAL` compares the value and applies `SET`, with optional TTL | Connections to the same Redis key; EVAL permission is required |

The File lock provides process concurrency within one BEAM. It does not add
power-loss durability. ETS does not survive a BEAM exit. Deletion and Redis
expiry remove revision history. These checks do not establish a writer lease
across record lifetimes, or prove distributed failover and partition behavior.
Those remain separate `SDK-CLUSTER` questions.

## Validation

| Check | Result |
| --- | --- |
| Focused persistence, instance, context, Runtime, and Multi-agent tests | 89 passed; no skips |
| Runtime examples | 29 passed; no skips |
| Multi-agent examples | 18 passed; no skips |
| Local Redis 8.6.2 checks | 2 passed |
| Full suite, seed 0, default concurrency | 859 of 862 passed; 34 research skips; 3 failures |
| Full suite, seed 0, `--max-cases 1` | 860 of 862 passed; 34 research skips; 2 failures |
| `mix quality` | Passed; no application compile warnings or Dialyzer errors |
| `mix docs --no-open` | Passed |
| Formatting, diff whitespace, and example Markdown links | Passed; 1,139 local links resolve |

Both full runs retain the known Fixed Group and Elastic Group failures. The
concurrent run also times out at the 100 ms delivery assertion in
[ServerContextTest](../../test/jido/agent_server_context_test.exs). That test
passes in the focused and serial runs and does not configure persistence.
Its timing needs a separate check; its assertions and timeout were not changed.
The full suite still emits five existing test compiler warnings for deliberate
invalid inputs and redundant assertions. The [gap register](runtime-multi-agent-gaps.md)
records the remaining failures.

The persistence tests cover exact byte comparison, concurrent creation and
replacement, stale and equal revisions, expected revision mismatch, missing
records, corrupt records, adapter errors, and adapter configuration. Barriers
hold two saves after the same read and prove that only one can commit.
The Server test checks rejected commit, no Directive delivery, unchanged live
state, rejected hibernate, and preservation of the winning record after stop.

The instance Redis test double now implements the conditional command contract.
Two additional local checks ran against **Redis 8.6.2**, using the actual Lua
script and separate socket connections. They verified binary values, TTL
application and preservation after conflict, and one winner among 16 concurrent
connections for both creation and replacement. These checks used one local
Redis process; no cluster or failover test ran.

Commands for repository checks:

```shell
mix test --include integration test/jido/persistence_test.exs test/jido/persistence test/jido/instance_test.exs test/jido/agent_server_context_test.exs test/examples/04_runtime test/examples/05_multi_agent --seed 0
mix test --include example --include integration --seed 0
mix test --include example --include integration --seed 0 --max-cases 1
mix quality
mix docs --no-open
```

Validation used Elixir 1.20.3 and OTP 29. The release baseline remains Elixir
1.18 and OTP 27+. Core edits in this follow-up are limited to persistence,
its three adapters, and the Server persistence write path and documentation.
Earlier working-tree changes remain intact. No dependency change was needed.
