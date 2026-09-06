# Round 18: Reserved context keys

Decision: **accepted**.

The valid command path checked three reserved keys by building and filtering a
list of every context key. It now checks membership for those three keys first.
The invalid path retains the original key list, order, message, and details.

Five fresh-VM short-profile pairs selected `command/context`. The unchanged-code
control used the same scripts and settings. Its case median time ratios were
0.959 to 1.000. Some individual pairs had wider variation. The 1,000-key prepare
case improved in four pairs, and the 10,000-key case improved in all five. Their
median gains were 36% and 88%. The other case medians changed by less than 2%.
The 1,000-key p95 did not improve; no p95 gain is claimed for that case.

| Context keys / mode | Time ratio | Faster pairs | p95 ratio | Caller reduction ratio | GC before / after |
| --- | ---: | ---: | ---: | ---: | ---: |
| 0/prepare | 1.018 | 2/5 | 1.018 | 1.002 | 25 / 25 |
| 0/reject | 1.005 | 2/5 | 0.902 | 1.001 | 22 / 22 |
| 1000/prepare | 0.636 | 4/5 | 1.038 | 0.591 | 8 / 7 |
| 1000/reject | 1.009 | 2/5 | 1.028 | 1.001 | 9 / 9 |
| 10000/prepare | 0.116 | 5/5 | 0.165 | 0.126 | 0 / 0 |
| 10000/reject | 1.013 | 2/5 | 1.036 | 1.000 | 2 / 2 |

All sampled process-peak ratios were 1.000. Valid result copy sizes and observed
shared binary bytes were unchanged. Error copy size fell, but exception
stacktrace shape can change when a branch changes. That result is not used as
memory evidence. No helper processes started or remained in these workloads.
GC counts include setup and result checks; they are not allocation totals.

All 116 focused Agent, Server, context, Plugin, and benchmark tests passed.
The new test checks all 1,000 caller fields and rejects each reserved key even
when its value is nil. Each workload checks complete results and cleanup.
Complete quality and core coverage checks are due before this fix is pushed.

Evidence: `bench/results/round-18` and `bench/results/round-18-control`.

Baseline commit: `def4d6fb46fffaac63199097df8916348aa0e470`.
Runtime SHA-256: `4b7d9b1cd998aeae8814157157590586523deb38e318aa8d50bae9168dac5eb4`.

Candidate commit: `eab7aa53a8c94112181a4e824a4da99b16da4b61`.
Runtime SHA-256: `6d26271e176c0fb33ef48ff181e0a1843bb7fc7144dfb0b62ce1f660ac816696`.

Tool SHA-256: `2c9090866787aece532c594911bbb9639bd17a58d28f993fd511b6f265816c14`.
Lock SHA-256: `1b7d690225a5ee1900d268df23766e92aa6951f541e018f7a65d950c18c66953`.
Elixir 1.20.3, OTP 29, Apple M1 Max, two schedulers, Mix dev.
