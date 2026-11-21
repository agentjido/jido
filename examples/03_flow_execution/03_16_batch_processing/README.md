# 03_16 Batch Processing

A bounded Map transforms one hundred values, and a Reduce produces their
ordered total.

## What you will learn

- How Map keeps a runtime-sized collection inside one Flow.
- How `max_concurrency` bounds parallel work before an ordered Reduce.

## Read the code

Read [the Flow](batch_processing.ex) first. Then read
[the concurrency proof](batch_processing_test.exs).

## Run it

`mix test.examples examples/03_flow_execution/03_16_batch_processing --warnings-as-errors`

Expected result: no more than four Map items start before release, output order
matches input order, and the final total is `10_100`.

## Important behavior

The test uses local coordination messages only as a deterministic concurrency
barrier. The Flow output stays independent of that test barrier.

## Limits

This lesson does not measure throughput or prove a distributed concurrency
limit. The barrier in the main source must move to local test support in a
later public-API cleanup pass.

## Core Fit and Gaps

Map, ordered results, and Reduce compose through the public Flow contract. The
test barrier currently leaks process coordination into reader-facing Action
code. This is application test scaffolding, not a Jido core API gap.

## Files

- [Flow](batch_processing.ex)
- [Tests](batch_processing_test.exs)
