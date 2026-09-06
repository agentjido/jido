# Round 10: Trim the old Audit prefix before append

Decision: **rejected after measurement**. No change from this trial was kept.

The trial counted the new records. For batches below the limit, it used
`Enum.take/2` to retain only the old suffix before concatenation. Larger batches
used the original append-and-take path.

Baseline: `b4b8c1d3`. Trial: `bedabf2e` (unpublished experiment, removed).
Five fresh-VM pairs used the short profile and all Audit update cases. Local
evidence: `bench/results/round-10`. Source and tool hashes are in its reports.
The tool and host settings match `round-09-final`.

Time ratios for a 1,000-record existing buffer were 1.604 for one new record,
1.526 for 100 new records, 1.383 for 1,000 new records, and 1.391 for 1,100 new
records. None of those five-pair sets improved. Sampled process memory and
copied result size were unchanged. All 13 focused tests and all result and
cleanup checks passed, but the time regressions reject this implementation.

Round 11 will test only the full-new-batch path. It will keep the original
append-and-take path for small incoming batches.
