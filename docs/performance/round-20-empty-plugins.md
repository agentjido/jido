# Round 20: Empty Plugin normalization

Decision: **rejected**.

The trial added `normalize_all([]), do: {:ok, []}` before the general list
clause. This removed empty normalization and uniqueness steps. It preserved
results in all 103 focused Plugin, schema, Agent, and benchmark tests.

Five fresh-VM short-profile pairs covered 65 Agent cases. Small command
preparation improved by about 5%, and small direct commands by about 6%.
The broad check found larger regressions: large-map preparation used 3.43 times
the median time, and large-map transitions used 3.92 times the time, in all
five pairs. Several sampled process peaks also increased. The unchanged-code
control did not show those large effects.

| Selected case | Time ratio | Faster pairs | Control time ratio | Sampled process-peak ratio |
| --- | ---: | ---: | ---: | ---: |
| agent/new/routes_1/small | 0.952 | 5/5 | 0.997 | 1.855 |
| agent/validate/routes_1/small | 0.962 | 5/5 | 1.000 | 1.427 |
| agent/prepare/routes_1/small | 0.946 | 5/5 | 1.004 | 0.330 |
| agent/cmd/routes_1/small | 0.937 | 4/5 | 1.032 | 1.013 |
| agent/prepare/routes_1/large_map | 3.434 | 0/5 | 1.003 | 1.000 |
| agent/transition/routes_1/large_map | 3.919 | 0/5 | 0.987 | 0.382 |
| agent/route/routes_1/large_list | 1.104 | 0/5 | 1.015 | 1.000 |
| agent/checkpoint/routes_1/large_binary | 0.980 | 4/5 | 1.008 | 5.150 |

All copied result sizes were unchanged. The same scripts and settings ran on
both sides, with a full caller GC after setup before timing. Resource peaks
include setup and result checks. Removing allocation from setup can change
later heap and GC behavior; these measurements do not identify the exact cause
of each peak change. The measured regression is sufficient to reject this
candidate for the current suite. No overall speed or memory gain is claimed.

The runtime edit was removed. The patch is
`trials/round-20-empty-plugins.patch`; use `git apply --unidiff-zero` on the
stated baseline to reproduce it. Evidence is in `bench/results/round-20` and
`round-20-control`.

Baseline commit: `3529f146eead9969ac5cbb6c0b10f2ab6aea9671`.
Runtime SHA-256: `5ee487bd5c22eff08aaeb516de5bfdaa5f953d5c36d214f8e26b35b1bea842d4`.

Candidate commit: `e9f71347326b36cf7ee36deb200ead4e3ca98c32`.
Runtime SHA-256: `4cb27ed9e82df5339b66ff537848011e949489d4ee6657b2398356527db2e480`.

Tool SHA-256: `4c6af3984b0bea872be2d77ce781b6d515230f0240615c54a47843a6be265d1b`.
Lock SHA-256: `1b7d690225a5ee1900d268df23766e92aa6951f541e018f7a65d950c18c66953`.
Elixir 1.20.3, OTP 29, Apple M1 Max, two schedulers, Mix dev.
