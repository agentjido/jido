# Round 01: Thread normalization

Status: **rejected**. The original runtime implementation is retained.

The existing `normalize_many/4` first builds `{entry, index}` tuples and a list,
then builds the final Entry list. The hypothesis is that removing the intermediate
list reduces memory and execution time without changing entries or ID calls.

Baseline: `4a00feb3`, which contains the benchmark suite and no runtime change.
The selected scale cases cover normalization, append, last entry, and slice at
1, 100, 1000, and 10000 entries. Forty-five focused tests passed, including a new
check for generator order, existing IDs, timestamps, and empty input.

## Variants

1. `Enum.with_index/2` with a callback: tested in five fresh-VM pairs. Some large
   cases improved, but 100-entry normalization was slower. Do not ship this form.
   Local reports: `bench/results/round-01/`.
2. Direct list recursion: tested in five pairs. Time samples were sensitive to
   garbage left by untimed setup. These version-1 time samples are exploratory.
   Local reports: `bench/results/round-01-direct/`.
3. Repeat direct recursion with measurement schema 2. Each time sample collects
   caller garbage after setup, before starting its clock. Server and worker
   heaps are not forced to collect. The same current scripts run against both
   source revisions. A five-pair unchanged-code control precedes five candidate
   pairs. Raw reports: `round-01-control-v2` and `round-01-direct-v2` under
   `bench/results/`.

The post-GC method defines the caller conditions. It does not measure natural
long-lived caller heap pressure. Separate resource calls retain the original
setup, operation, callback barriers, result checks, and cleanup measurements.

The schema-2 direct-recursion result improved 100- and 1000-entry normalization
in all five pairs. However, 10000-entry append was slower in all five pairs.
A constant-stack accumulator with one final reverse is the next variant.
Its reports are in `bench/results/round-01-tail-v2/`. Do not accept the direct
recursion variant without resolving the append result.

## Decision

No variant met all acceptance checks. The constant-stack form increased sampled
process memory by 49.9% in the 1000-entry normalization and append cases. The
unchanged-code memory ratios were exactly 1.0 in all five control pairs. It also
increased memory by 23.6% for 10000-entry append. This is sufficient reason to
reject it despite gains in other cases.

The direct-recursion form reduced time in medium cases but left a large-append
regression unresolved. The host control was too variable at 10000 entries to
support a large-case time claim. Do not infer an overall speed gain from these
runs. Preserve the additional ID-order regression test for later experiments.

This round tested three forms. It does not prove that no other implementation
can improve normalization.
