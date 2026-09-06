> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Persistent Counter Recovery

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_07_persistent_counter_recovery`
- **Status:** doesn't work yet
- **Complexity level:** 3 - Runtime
- **Feature group:** runtime
- **Test class:** local deterministic

## Profile

- **Purpose:** Restore a Counter and continue without duplicate state changes.
- **User story:** As an operator, I restart the Actor and keep the exact last committed count.
- **Trigger or input:** Counter Signals before and after an Actor Server restart.
- **Agent state:** Count, version, handled Signal IDs, and last command.
- **Actions or Flow:** One Action applies a unique command and returns the complete state.
- **External interactions:** Jido persistence adapter. Tests use an isolated ETS fixture.
- **Runtime Directives or capabilities:** None for the count. Restore is a Server capability.
- **Expected result:** The restored value equals the last durable commit. Duplicate Signals preserve state and create one new commit revision.
- **Failure cases:** Corrupt snapshot, stale write authority, duplicate command, missing snapshot, or version conflict.
- **Jido features under pressure:** Persistence adapters, restore, state version, idempotency, and structured restore errors.
- **Source framework and links:** [Akka: event sourcing recovery concepts](https://doc.akka.io/libraries/akka-core/current/typed/persistence.html), [Jido implementation](../../../../examples/04_runtime/04_06_state_recovery/persistent_counter_recovery.ex), and [Jido test](../../../../test/examples/04_runtime/04_06_state_recovery/persistent_counter_recovery_test.exs)

## Burn-in result

Four local tests pass. The Actor restores its exact count, handled Signal IDs,
last command, and state version. A duplicate Signal after restore does not
change the Actor value. It advances the commit revision from 1 to 2. The test
loads the stored record before hibernation, then restores it again. Both reads
retain revision 2. Invalid input leaves the Actor and stored revision unchanged.
Missing and corrupt records return errors.

The original burn-in skipped the stale-writer test. The approved
[persistence fix](../../persistence-write-results.md) adds `compare_and_swap/4`
and expected revision checks. All five current State Recovery tests now pass.

A duplicate command returns the same state as a successful result.
`state_version` means commit revision. Every successful Turn advances it once,
including an identical-state result. The Server and persistence documentation
now define this rule from [issue #15](https://github.com/mikehostetler/jido_v3/issues/15).
An application that requires no commit for a duplicate can return
`{:error, reason}` before commit. A failed post-commit Directive does not undo
a commit. No new no-op result is required.

## Best-effort implementation

- [Code](../../../../examples/04_runtime/04_06_state_recovery/persistent_counter_recovery.ex)
- [Tests](../../../../test/examples/04_runtime/04_06_state_recovery/persistent_counter_recovery_test.exs)

The current fixture passes with real SDK persistence. Stale writes cannot
replace newer records. ETS retains data only for the BEAM lifetime; distributed
leases and crash durability require separate storage and lifecycle tests.

An example-scope gap is not evidence of a core Jido defect.

Current feature: [State Recovery](../../profiles/04_runtime/04_06_state_recovery.md).
