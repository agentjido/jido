# Round 02: Count appended entries once

Decision: **rejected after measurement**. No runtime change was retained.

The candidate stored `length(prepared_entries)` once and used it for revision
and cached count updates. Baseline: `99b92e80`. Trial: `2f1a4681` (unpublished
experiment). The trial was removed before shipping the decision.

Five fresh-VM pairs used the scale profile and `thread/append` filter. The tool
hash was `1e17fe878a82107a2dbe9f4209e9aa2464de525238297a885491538347c0b306`.
The runtime and lock matched Round 07. Raw reports, source hashes, logs, and
pair order are in `bench/results/round-02`.

| Batch size | Batch time ratio | Lower-time pairs | Process-byte ratio |
| ---: | ---: | ---: | ---: |
| 1 | 1.000 | 0/5 | 1.000 |
| 100 | 1.005 | 2/5 | 1.000 |
| 1,000 | 1.003 | 1/5 | 1.000 |
| 10,000 | 0.999 | 3/5 | 1.000 |

Caller reductions fell by about 0.15% for larger batches. Copied result size
was unchanged. No target passed the 5% time gain and four-of-five direction
gates. The 10,000-entry single-append case had a time ratio of 0.922, but only
three pairs improved and caller reductions were unchanged. This large case is
also variable in the unchanged-code control. It is not evidence for this change.

Thread and benchmark contract tests passed, as did all paired result and
cleanup checks. The source remains as it was before this trial.
