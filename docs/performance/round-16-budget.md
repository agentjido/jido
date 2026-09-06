# Round 16: Read a module budget once

Decision: **accepted**.

`StateBudget.check/1` now reads the module limit once, validates that value,
and uses it to select the smaller limit. Instance limit validation still runs
first. A nil effective limit still skips state measurement. State size still
uses `:erlang.external_size/1`.

Five fresh-VM short-profile pairs selected both single checks and the new
100-operation batches. Small-state check batches improved by 21% to 24% in all
five pairs. Small-state transition batches improved by 7% to 16% in at least
four pairs. Large state with no limit also improved. Large state with a limit
spends most of its time measuring bytes; those case medians changed by less
than 3%. The unchanged-code control case medians ranged from 0.979 to 1.018.

| Case | Time ratio | Faster pairs | p95 ratio | Caller reduction ratio |
| --- | ---: | ---: | ---: | ---: |
| budget/nil | 1.000 | 1/5 | 1.000 | 0.731 |
| budget/2000000 | 1.002 | 1/5 | 1.032 | 0.750 |
| budget_batch/small/unlimited/check | 0.758 | 5/5 | 0.769 | 0.703 |
| budget_batch/small/unlimited/transition | 0.840 | 5/5 | 0.851 | 0.797 |
| budget_batch/small/module/check | 0.786 | 5/5 | 0.843 | 0.683 |
| budget_batch/small/module/transition | 0.925 | 5/5 | 0.893 | 0.796 |
| budget_batch/small/stricter/check | 0.767 | 5/5 | 0.777 | 0.683 |
| budget_batch/small/stricter/transition | 0.900 | 4/5 | 0.927 | 0.794 |
| budget_batch/large_list/unlimited/check | 0.603 | 5/5 | 0.614 | 0.697 |
| budget_batch/large_list/unlimited/transition | 0.811 | 5/5 | 0.843 | 0.795 |
| budget_batch/large_list/module/check | 1.014 | 2/5 | 1.005 | 0.678 |
| budget_batch/large_list/module/transition | 1.022 | 1/5 | 1.017 | 0.778 |
| budget_batch/large_list/stricter/check | 1.016 | 2/5 | 1.023 | 0.678 |
| budget_batch/large_list/stricter/transition | 0.989 | 4/5 | 0.979 | 0.778 |

All sampled process-peak and copied-result ratios were 1.000. There were no
owned helper starts or remaining helpers. No memory reduction is claimed.
All 73 focused budget, Agent, and benchmark tests passed. Budget tests cover
exact limits, oversized state, module precedence, replacement ownership,
Plugin state, checkpoints, and restoration. Each batch checks all 100 results.
The [complete checks](phase-34-checks.md) passed with 83.5% core coverage.
The same 11 known example failures remain outside that coverage gate.

Evidence: `bench/results/round-16` and `round-16-control`.

Baseline commit: `6f52a85bf46ed2dd9892996018468faa5112f0b0`.
Runtime SHA-256: `fa35269085c20b740ef757e10c37073cf89e3ba937d65cf300b0a5d326668c6c`.

Candidate commit: `3e58775f8a34f67288d921f07d1499bf44f142e8`.
Runtime SHA-256: `9452e74af75139d30d4a781976b8410f5c491dbbc9a727ddf38b185693dcc82e`.

Tool SHA-256: `1c99f553697d7ee2c4c2521f1e7c4ad4e14c823779ff03dac24124d3010a7d1c`.
Lock SHA-256: `1b7d690225a5ee1900d268df23766e92aa6951f541e018f7a65d950c18c66953`.
Elixir 1.20.3, OTP 29, Apple M1 Max, two schedulers, Mix dev.
