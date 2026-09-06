# Round 36: Default ETS table name

Decision: **accepted**.

The default persistence table name was rebuilt through string interpolation
on each operation. The new branch returns the existing atom directly for
both omitted table options and an explicit default base. Custom table names
use the existing path. Table creation, exact-byte CAS, and error handling stay.

Five fresh-VM short-profile pairs covered 12 cases, each with 100 operations.
Default and explicit-default cases improved by 30% to 66% in all five pairs.
Custom-table case medians stayed within 1% of the baseline. Unchanged-code
control medians ranged from 0.973 to 1.029; all control process-byte ratios
were 1.000.

| Table / operation / batch | Time ratio | Faster pairs | p95 ratio | Caller reduction ratio | Sampled process-peak ratio |
| --- | ---: | ---: | ---: | ---: | ---: |
| default/get/100 | 0.443 | 5/5 | 0.586 | 0.585 | 0.635 |
| default/put/100 | 0.341 | 5/5 | 0.548 | 0.563 | 1.000 |
| default/cas/100 | 0.679 | 5/5 | 0.696 | 0.593 | 1.000 |
| default/conflict/100 | 0.659 | 5/5 | 0.739 | 0.577 | 1.000 |
| explicit_default/get/100 | 0.457 | 5/5 | 0.606 | 0.585 | 0.736 |
| explicit_default/put/100 | 0.345 | 5/5 | 0.380 | 0.563 | 1.529 |
| explicit_default/cas/100 | 0.696 | 5/5 | 0.733 | 0.593 | 1.000 |
| explicit_default/conflict/100 | 0.637 | 5/5 | 0.636 | 0.577 | 1.000 |
| custom/get/100 | 1.001 | 2/5 | 1.032 | 1.000 | 1.000 |
| custom/put/100 | 0.991 | 4/5 | 0.990 | 1.000 | 1.000 |
| custom/cas/100 | 1.006 | 2/5 | 0.942 | 1.000 | 1.000 |
| custom/conflict/100 | 0.991 | 3/5 | 0.991 | 1.000 | 1.000 |

The explicit-default put batch had a higher sampled process peak: 5,704 to
8,720 bytes. Its copied result stayed at 1,600 bytes. This workload retains a
list of 100 status results. A separate write-loop diagnostic checks each result
without retaining that list. Across five fresh-VM pairs and 100, 1,000, and
10,000 writes, both versions used a sampled peak of 5,704 bytes. GC counts
changed from 8 to 4, 72 to 31, and 715 to 301. The same values repeated in all
pairs. This supports keeping the large time gain while recording the 3,016-byte
increase in the original batch. Do not claim lower peak memory for every put
workload, or an exact allocation reduction.

All copied results were unchanged. No owned helper remained. ETS table memory
is outside these per-case process measurements. Each benchmark deletes its
own key; named tables remain VM infrastructure. The 42 focused persistence,
schema, and benchmark tests passed, including concurrent CAS, table isolation,
table ownership, and full Agent persistence. The complete checks passed with 893 core tests and 83.5% core coverage.
See [the phase checks](phase-40-checks.md).

Evidence: `bench/results/round-36`, `round-36-control`, and `round-36-puts`.
The resource-only follow-up is `docs/performance/probes/round-36-puts.exs`.

Baseline commit: `9860f5c113f52b6c4990b1eee032826d392e454a`.
Runtime SHA-256: `5ee487bd5c22eff08aaeb516de5bfdaa5f953d5c36d214f8e26b35b1bea842d4`.

Candidate commit: `763e351e8eac06d7979342a4b50ab6473890ee87`.
Runtime SHA-256: `d2c12025f34d3c55654fd9d80685eac096ef374bb6cff12343aa3b067d0d3447`.

Tool SHA-256: `2918aeda2fa33cb8b49fbc0008b11aa8406de2b4a46b18617dd5075ae84e3c3c`.
Lock SHA-256: `1b7d690225a5ee1900d268df23766e92aa6951f541e018f7a65d950c18c66953`.
Elixir 1.20.3, OTP 29, Apple M1 Max, two schedulers, Mix dev.
