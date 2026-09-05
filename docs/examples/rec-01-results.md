> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# REC-01: explicit delivery recovery

Date: **2026-09-04**. Status: **Implemented with current core**.

The user selected an explicit Plugin capability after review of the original
universal outbox proposal. The original probe proved that ordinary Directives
are not recovered. That behavior is now an explicit limit, not a requirement
to add an automatic core outbox.

## Contract and example

The [Agent and Output Plugin](../../lib/examples/04_runtime/04_11_recoverable_delivery/recoverable_delivery.ex)
commit business state and pending delivery intent in the same Agent checkpoint.
`Output.update_state/3` records the application's stable effect ID and value.
A conflicting reuse of that ID rejects the whole candidate before commit.

The [supervised worker](../../lib/examples/04_runtime/04_11_recoverable_delivery/delivery_worker.ex)
reads committed Plugin state on startup and at each poll. A Deliver Directive
only wakes it. A lost wake-up cannot lose the saved work. The worker makes one
attempt at a time, rotates IDs, polls at 100 ms, and limits an attempt to five
seconds. The policy is explicit and small; it is not a general job service.

A receiver reply of `:ok` means the example sink accepted the write. The worker
then sends the generated `confirm_delivery` Signal. That Turn records completion
and advances the normal Agent revision. No storage cursor or new core API is
needed. Later business Turns retain earlier pending entries.

A crash after the write but before committed confirmation can repeat delivery.
The sink accepts the same ID/value again without adding another record and
rejects an ID with a different value. Completed IDs remain in Plugin state in
this example. Production code must define retention and capacity policy.

## Verification

```shell
mix test test/jido/agent/effect_recovery_test.exs --seed 0
mix run lib/examples/04_runtime/04_11_recoverable_delivery/demo.exs
```

The [tests](../../test/jido/agent/effect_recovery_test.exs) pass **11 cases, with
no skips**:

1. Pure evaluation returns a candidate with business state and Plugin intent.
2. Confirmation checks the saved ID/value and permits an identical repeat.
3. Completed IDs prevent another delivery and reject conflicting changes.
4. Agent loss before the external write resumes the same pending effect.
5. Agent loss after the external write retries it without another sink record.
6. Completed work stays complete after another activation.
7. Plugin loss restarts delivery while the Agent remains alive.
8. New Turns commit while delivery is blocked and preserve older pending work.
9. An unavailable sink is retried from saved intent.
10. A failed intent write exposes no work to the live Plugin.
11. A failed completion write keeps pending intent and retries the same effect ID.

The persistence fault wrapper delegates storage to the real File adapter. It
injects known failures before mutation; it does not replace checkpoint or
restore behavior. Crash barriers hold real worker Tasks. Tests monitor their
exit and read actual persisted Agent revisions.

The runnable probe crashes after the sink write, starts a fresh Agent, and
shows automatic retry followed by committed confirmation. It leaves one sink
record and removes its temporary storage directory.

## Design change

[Commit and effects](../design/commit-and-effects.md) and
[Durability guarantee](../design/durability-guarantee.md) now separate ordinary
Directive dispatch from explicit recoverable work. Related design documents
remove the universal outbox, cursor, and admission gate. Unrelated proposed
instance APIs and write-authority rules remain proposals. Modified design
documents remain Pending approval under `docs/design/AGENTS.md`.

## Limits

This proof uses one BEAM and the File adapter. The sink stays alive outside the
failed Agent. It does not prove fresh-VM recovery, sink persistence, power-loss
durability, shared storage across nodes, exactly-once effects, or distributed
write authority. Later activation and available dependencies are conditions of
completion. Cross-restart trace continuity is outside REC-01.

An indeterminate storage write needs an authority policy; it is not equivalent
to the known failed writes injected here. No new claim is made for that boundary.

Core and dependency files are unchanged by this implementation. The previous
DIST-01 and OBS-01 changes remain in the working tree. The main example ladder
and existing full-suite limits are recorded separately.

## Combined validation after continuation

The earlier focused run, before the Scheduler identity extension, included Basic through Multi-agent, DIST-01, DIST-02,
OBS-01, REC-01, REC-02, and the REC-03 probe. It reports **218 of 219 passing,
no skips**. Its only failure was REC-03's missing Scheduler occurrence ID.
That identity gap is now resolved; see the [current REC-03 result](rec-03-results.md).
The main five groups retain their 170 passes. This is not a full-suite result.

`mix quality` and `mix docs --no-open` pass. The delivery script exits with
status 0. All 92 core and dependency files match the baseline saved before
this Plugin implementation. Local Markdown links and Git whitespace pass.
