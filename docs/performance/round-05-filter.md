# Round 05: Single-kind Thread filtering

Decision: **accepted**.

The atom-kind clause now filters by strict equality. It no longer builds a
one-item list or uses list membership for each entry. The list-kind clause
stays unchanged. Strict equality preserves the existing `in` comparison.

Five fresh-VM scale-profile pairs selected all mixed-kind filter cases. At
100 to 10,000 entries, single-kind and missing-kind calls used 39% to 49% less
median time in all five pairs. The one-entry values are below useful timer
resolution for this claim. The unchanged-code control medians were 0.996 to
1.027. Multiple-kind results stayed within that range.

| Entries / mode | Time ratio | Faster pairs | p95 ratio | Caller reduction ratio |
| --- | ---: | ---: | ---: | ---: |
| 1/single | 1.000 | 0/5 | 0.500 | 0.778 |
| 1/multiple | 1.000 | 0/5 | 1.000 | 1.000 |
| 1/missing | 1.000 | 0/5 | 0.500 | 0.765 |
| 100/single | 0.536 | 5/5 | 0.531 | 0.533 |
| 100/multiple | 1.000 | 1/5 | 1.000 | 1.000 |
| 100/missing | 0.518 | 5/5 | 0.484 | 0.507 |
| 1000/single | 0.601 | 5/5 | 0.576 | 0.527 |
| 1000/multiple | 1.000 | 3/5 | 1.043 | 1.000 |
| 1000/missing | 0.515 | 5/5 | 0.511 | 0.501 |
| 10000/single | 0.610 | 5/5 | 0.551 | 0.526 |
| 10000/multiple | 1.002 | 1/5 | 1.024 | 1.000 |
| 10000/missing | 0.540 | 5/5 | 0.546 | 0.500 |

All process-peak and copied-result ratios were 1.000. No helper processes
started or remained. Result checks compare all selected entry IDs and kinds
in order. All 41 Thread and benchmark tests passed, including nil input,
invalid input, no matches, and multiple kinds. The [complete checks](phase-34-checks.md) passed with 83.5% core coverage.
The same 11 known example failures remain outside that coverage gate.

Evidence: `bench/results/round-05` and `round-05-control`.

Baseline commit: `6b999a4e01ca19a2d21edd4299f03ad14862dd59`.
Runtime SHA-256: `4b544c1ef6236ed9ef826748e6a7bc444b1e5cedca6ae971eb3a3806387e4c01`.

Candidate commit: `3b4321dafab994702966ed198342e99bcc0517dc`.
Runtime SHA-256: `fa35269085c20b740ef757e10c37073cf89e3ba937d65cf300b0a5d326668c6c`.

Tool SHA-256: `2c9090866787aece532c594911bbb9639bd17a58d28f993fd511b6f265816c14`.
Lock SHA-256: `1b7d690225a5ee1900d268df23766e92aa6951f541e018f7a65d950c18c66953`.
Elixir 1.20.3, OTP 29, Apple M1 Max, two schedulers, Mix dev.
