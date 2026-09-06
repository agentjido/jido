# Round 11: New Audit batches that fill the buffer

Decision: **rejected after measurement**. No runtime change was kept.

Both trials counted the incoming records and skipped the old buffer when the
new batch filled the limit. For smaller batches, the first trial used the
original append-and-take path. The second used the known incoming count to
compute how many old records to drop before append.

Baseline: `b4b8c1d3`. Trial commits: `79bc0af2` and `f24d6590` (unpublished
experiments, removed). Each trial used five fresh-VM pairs with all nine Audit
update cases in the short profile. Local evidence: `bench/results/round-11`
and `round-11-final`. Their reports contain full source, tool, and lock hashes.
The tool and host settings match Round 09.

| Existing / new records | First trial time ratio | Second trial time ratio |
| --- | ---: | ---: |
| 1 / 100 | 1.743 | 1.000 |
| 1,000 / 1 | 1.021 | 1.590 |
| 1,000 / 100 | 1.074 | 1.520 |
| 1,000 / 1,000 | 0.442 | 0.432 |
| 1,000 / 1,100 | 0.455 | 0.452 |

The full-batch gains occurred in all pairs, but so did the partial-batch
regressions. The revised path removed the first trial's small-buffer regression
and made updates to an existing full buffer slower. Sampled process memory and
copied results were unchanged. All 13 focused tests and all paired result,
transfer, and cleanup checks passed. Neither trial met the cross-case gate.

The accepted empty-update path from Round 09 remains. Nonempty updates retain
the original append-and-take implementation.
