# Round 22: Reuse a composed instance schema

Decision: **rejected**.

The trial returned the composed schema from common Agent validation and used
it for the instance state parse. It removed one composition pass. It kept
state parsing and public definition validation. All 104 focused Plugin,
schema, Agent, and benchmark tests passed.

Five fresh-VM short-profile pairs covered 65 Agent cases and seven Plugin
cases, with unchanged-code controls for each group. The zero-item owned-state
validation case improved by 27% in four pairs. The broad check failed: direct
large-map commands were 62% slower, and large-map transitions used 3.93 times
the median time, in all five pairs. Several sampled process peaks increased.

| Selected case | Time ratio | Faster pairs | Control time ratio | Sampled process-peak ratio |
| --- | ---: | ---: | ---: | ---: |
| agent/validate/routes_1/small | 0.948 | 5/5 | 1.026 | 1.000 |
| plugin/schema/0/validate | 0.734 | 4/5 | 1.005 | 0.457 |
| plugin/schema/0/prepare | 0.809 | 3/5 | 1.004 | 0.472 |
| plugin/schema/1000/validate | 0.984 | 3/5 | 0.998 | 1.000 |
| plugin/schema/1000/prepare | 0.955 | 4/5 | 0.999 | 1.117 |
| plugin/schema/10000/validate | 1.034 | 1/5 | 0.976 | 1.000 |
| plugin/schema/10000/prepare | 0.995 | 3/5 | 0.983 | 1.000 |
| agent/cmd/routes_1/large_map | 1.624 | 0/5 | 1.009 | 1.000 |
| agent/transition/routes_1/large_map | 3.926 | 0/5 | 1.002 | 0.334 |
| agent/flow/routes_1/small | 0.974 | 4/5 | 0.993 | 2.144 |
| agent/checkpoint/routes_1/large_binary | 0.898 | 5/5 | 0.988 | 4.622 |

Copied results were unchanged. Timed calls follow a full caller GC after
setup; resource observations include setup and checks. The measurements do
not isolate the cause of the heap and GC changes. The broad regressions reject
this candidate despite the improvement in the small owned-state case.

The runtime edit was removed. The new schema contract test was kept. It checks
that changed Plugin options and domain schemas take effect on the next
validation call. The trial patch is `trials/round-22-schema-reuse.patch`.
Apply it with `git apply --unidiff-zero` to the stated baseline for study.

Evidence: `bench/results/round-22-agent`, `round-22-plugin`,
`round-22-control-agent`, and `round-22-control-plugin`.

Baseline commit: `9860f5c113f52b6c4990b1eee032826d392e454a`.
Runtime SHA-256: `5ee487bd5c22eff08aaeb516de5bfdaa5f953d5c36d214f8e26b35b1bea842d4`.

Candidate commit: `ca0e9a355fcc6dc2ded4056210724a82922b0531`.
Runtime SHA-256: `259bad2fb447a440d3c288b6079dca3ddacda6c8009d33491aefaab469a18ad4`.

Tool SHA-256: `2918aeda2fa33cb8b49fbc0008b11aa8406de2b4a46b18617dd5075ae84e3c3c`.
Lock SHA-256: `1b7d690225a5ee1900d268df23766e92aa6951f541e018f7a65d950c18c66953`.
Elixir 1.20.3, OTP 29, Apple M1 Max, two schedulers, Mix dev.
