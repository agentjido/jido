# 24_05 Compensation

An order reserves a resource and then confirms or releases it through an
explicit, idempotent settlement path.

## What you will learn

- How a Flow models compensation as normal business work.
- How one idempotency rule prevents a repeated reservation or release.

## Read the code

Read [the application Flow](compensation.ex) first. Then read
[the recovery proof](compensation_test.exs).

## Run it

`mix test.examples examples/24_application_patterns/24_05_compensation --warnings-as-errors`

Expected result: an accepted charge confirms its reservation. A rejected
charge releases its reservation once, including after managed execution
resumes.

## Important behavior

The ledger is the canonical state owner. Each operation has a stable
idempotency key. The recovery proof stops after reservation, restores progress,
and verifies that the reservation does not run twice.

## Limits

This example does not provide a distributed transaction or exactly-once
delivery. It does not define automatic compensation for an arbitrary Action
failure.

## Core Fit and Gaps

Choice, persistence of Flow progress, and application idempotency compose into
an explicit compensation path. The current recovery proof uses an internal
runner harness. A later pass must express the same stop and resume drill with a
public durable API before this is a complete public integration example.

## Files

- [Application Flow](compensation.ex)
- [Tests](compensation_test.exs)
