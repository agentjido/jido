> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# Persistence boundary probes

Current status (2026-09-05): **all 10 persistence probe tests pass**. Migration
preparation added nested identity checks, recursive load portability, and a
stop boundary for uncertain writers. The original assertions remain enabled.
See [preparation evidence](../migration/07-prepared-donor.md).

The remainder of this document records the original 2026-09-04 failure evidence.
It does not describe the current result.

The factory review produced three small core acceptance examples. All use an
application-owned in-memory byte adapter. They exercise real Jido checkpoint
encoding, loading, Agent evaluation, commit, and Directive dispatch. Database
adapters belong in integration packages such as `jido_ecto`. VM recovery is
outside this work.

| Capability | Passing controls | Enabled failure |
| --- | --- | --- |
| [PERSIST-01: identity](../../lib/examples/99_research/99_06_checkpoint_identity/README.md) | Valid identity, state, and revision restore; wrong envelope rejection | A correct envelope can contain a different nested Agent ID |
| [PERSIST-02: portability](../../lib/examples/99_research/99_07_checkpoint_portability/README.md) | Nested portable values round trip; save rejects a PID | Load accepts a nested PID supplied by storage |
| [PERSIST-03: indeterminate write](../../lib/examples/99_research/99_08_indeterminate_write/README.md) | Confirmed write permits output; uncertain reply preserves stored bytes and sends no Directive | The next Action evaluates stale state after an uncertain write |

## Run

```sh
mix test test/jido/persistence/checkpoint_identity_test.exs test/jido/persistence/checkpoint_portability_test.exs test/jido/persistence/indeterminate_write_test.exs --seed 0
```

Result: **6 passed, 3 failed, no skips**. Each failure is the intended acceptance
assertion for a current gap. These tests carry `:research` metadata and remain
enabled in the default suite. They do not assert the faulty behavior as success.
The example scripts report actual behavior and return normally for inspection.

The broader local check also ran the existing persistence adapter tests, State
Recovery, Runtime Inspection, Commit Outbox, and Bounded Workers:

```sh
mix test --include integration test/jido/persistence_test.exs test/jido/persistence test/examples/04_runtime/04_05_runtime_inspection test/examples/04_runtime/04_06_state_recovery test/examples/04_runtime/04_08_commit_outbox test/examples/05_multi_agent/05_03_bounded_workers --seed 0
```

Result: **54 passed, 3 failed**. The failures are the same three new acceptance
assertions. All three demo scripts ran and reproduced their stated gaps.
`mix q` passed, including Dialyzer. The 186 local links checked across the new
notes and updated indexes resolve. This change adds examples and tests; it
does not change the core persistence or Server implementation.

## Test boundaries

The identity and portability examples save a valid record, then change its
bytes through the adapter. This isolates load validation from save validation.
The identity test keeps the outer identity correct and changes only the nested
checkpoint ID. The portability test keeps its domain payload schema valid and
inserts one process handle below that schema.

The uncertain-write adapter performs one atomic compare-and-swap in an Agent
before returning `{:error, :indeterminate}`. The test confirms stored count `1`
at revision `1`, then submits a second command. An execution callback detects
the second Action even though its later write returns a conflict. Separate
Signal assertions cover post-commit output. No stopping error policy is added
to make the acceptance test pass.

The original required changes were to validate loaded identity and portability, and define
admission after an unknown write result. The current tests allow either stopping
the Server or rejecting further commands. They do not require a storage-specific
retry, VM lifecycle policy, or automatic reload.
