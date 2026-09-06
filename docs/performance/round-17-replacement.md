# Round 17: Replacement budget map updates

Decision: **rejected**, both trials.

The first trial replaced two `Map.put/3` calls with one `Map.merge/2`. The
second computed the module and limit before the two puts. Both preserved
replacement values in all 73 focused budget, Agent, and benchmark tests.
Each trial used five fresh-VM short-profile pairs and the same unchanged-code
control. The control case median time ratios ranged from 0.983 to 1.013.

| Trial | State / limit / operation | Time ratio | Faster pairs | p95 ratio | Sampled process-peak ratio |
| --- | --- | ---: | ---: | ---: | ---: |
| map merge | small/unlimited/transition | 1.061 | 0/5 | 1.026 | 1.000 |
| map merge | small/module/transition | 1.085 | 0/5 | 1.059 | 0.506 |
| map merge | small/stricter/transition | 1.061 | 0/5 | 1.009 | 0.506 |
| map merge | large_list/unlimited/transition | 1.032 | 0/5 | 1.040 | 1.000 |
| map merge | large_list/module/transition | 0.989 | 3/5 | 1.003 | 1.000 |
| map merge | large_list/stricter/transition | 1.002 | 2/5 | 0.987 | 1.000 |
| hoist | small/unlimited/transition | 1.004 | 2/5 | 1.007 | 1.000 |
| hoist | small/module/transition | 1.039 | 1/5 | 0.952 | 0.506 |
| hoist | small/stricter/transition | 1.035 | 1/5 | 0.925 | 0.506 |
| hoist | large_list/unlimited/transition | 1.000 | 2/5 | 1.014 | 1.000 |
| hoist | large_list/module/transition | 0.984 | 3/5 | 0.999 | 1.000 |
| hoist | large_list/stricter/transition | 1.019 | 2/5 | 1.009 | 1.000 |

The first trial slowed all three small-state transition cases by 6% to 9%.
The second gave no repeatable 5% time gain and no copied-result size gain.
Both lowered the sampled peak in two small-state transition batches, but this
is not an exact allocation or retained-copy measurement. That observation
alone does not pass the cycle's memory acceptance gate. All copied-result
ratios were 1.000. No helper processes started or remained.

The first trial's separate one-call nil-budget check changed from 42 ns to 83 ns
in three of the five pairs. Its 100-check batch did not show that slowdown. The single
call is too short for that ratio to support a useful performance claim.
The second trial's corresponding single-call ratio was 0.988.

Both runtime edits were removed. The original two-put path remains. Patches
are retained in `trials/round-17-map-merge.patch` and `trials/round-17-hoist.patch`.
Apply them to the stated baseline with `git apply --unidiff-zero` for study.

Evidence: `bench/results/round-17`, `round-17-hoist`, and `round-17-control`.

round-17: baseline `dbf0d71841052da5d6741857e812819f3e0cc607`, candidate `a7dd3f80f772ffd403968b2d7e1c90bf489d6804`.
Candidate runtime SHA-256: `1fc5a7acf7d77cd25991c3d2d59bb7d1216749fd68e6805e2ee1d2c652eff525`.

round-17-hoist: baseline `dbf0d71841052da5d6741857e812819f3e0cc607`, candidate `639861051dc09d0abf2493586828af7a4db07526`.
Candidate runtime SHA-256: `78d0a1f488ebebb7c97474fe500ae6727776b095dbf5689aa92158adbaf7de62`.

Tool SHA-256: `1c99f553697d7ee2c4c2521f1e7c4ad4e14c823779ff03dac24124d3010a7d1c`.
Lock SHA-256: `1b7d690225a5ee1900d268df23766e92aa6951f541e018f7a65d950c18c66953`.
Elixir 1.20.3, OTP 29, Apple M1 Max, two schedulers, Mix dev.
