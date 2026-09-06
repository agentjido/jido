# Round 31: Generated Codec definition validation

Decision: **accepted**.

Generated encoding validated the Agent, derived its Registry, then called the
public two-argument encoder, which validated the Agent again. Neutral
definitions now use a private encoder after the first validation. Public entry
validation, Registry validation, portable data checks, and document limits stay.
Complete instances keep their second state parse. Static schema transforms can
be non-idempotent. A test confirms that integer-to-string state transformation
still fails the second parse in generated encoding, as before.

Five fresh-VM scale-profile pairs selected all seven Codec cases. Generated
encoding improved in all five pairs at each route count. The unchanged-code
control case medians ranged from 0.974 to 0.997, with process-byte ratios of 1.000.

| Case | Time ratio | Faster pairs | p95 ratio | Caller reduction ratio | Sampled process-peak ratio |
| --- | ---: | ---: | ---: | ---: | ---: |
| codec/encode/1 | 1.001 | 2/5 | 1.037 | 1.000 | 0.627 |
| codec/decode/1 | 0.987 | 5/5 | 0.980 | 0.999 | 0.627 |
| codec/encode/16 | 0.998 | 3/5 | 0.927 | 1.000 | 1.169 |
| codec/decode/16 | 1.003 | 2/5 | 0.958 | 1.000 | 1.000 |
| codec/generated/1 | 0.712 | 5/5 | 0.746 | 0.735 | 1.000 |
| codec/generated/16 | 0.596 | 5/5 | 0.620 | 0.648 | 0.624 |
| codec/generated/64 | 0.571 | 5/5 | 0.597 | 0.617 | 0.765 |

The generated path used 29% to 43% less median time. Its 16-route and 64-route
sampled process peaks fell by 38% and 24%. Returned copied term sizes were
unchanged. There were no owned helper starts or remaining helper processes.

The supplied-registry 16-route workload had a 17% higher sampled process peak.
Its setup calls generated encoding, so the changed setup can alter the heap
and GC state before the observed call. A separate fixed-input diagnostic built
all inputs before resource observation. Across five fresh-VM pairs, the one-route
peak was 29,416 bytes on both sides; the 16-route peak was 55,000 bytes before
and 34,304 bytes after. This check found no supplied-encoder memory increase
with fixed input. The original workload's higher peak remains a measured
setup/operation interaction. Do not claim that every Codec workload uses less
peak memory. The accepted target has a large time gain and lower sampled memory
at the larger sizes. Sampled peaks are not exact allocation totals.

All 85 focused authoring, Agent, and benchmark tests passed. Each workload checks
complete decoded definitions or documents and process cleanup. Complete quality
and core coverage checks are due before this fix is pushed.

Evidence: `bench/results/round-31`, `round-31-control`, and `round-31-fixed`.
The fixed-input diagnostic is `docs/performance/probes/round-31-memory.exs`.
It supplies resource evidence only. Timing comes from the separate untraced runs.
The candidate includes Round 18, which changes only command context checks and
is not called by these Codec workloads.

Baseline commit: `def4d6fb46fffaac63199097df8916348aa0e470`.
Runtime SHA-256: `4b7d9b1cd998aeae8814157157590586523deb38e318aa8d50bae9168dac5eb4`.

Candidate commit: `6b999a4e01ca19a2d21edd4299f03ad14862dd59`.
Runtime SHA-256: `4b544c1ef6236ed9ef826748e6a7bc444b1e5cedca6ae971eb3a3806387e4c01`.

Tool SHA-256: `2c9090866787aece532c594911bbb9639bd17a58d28f993fd511b6f265816c14`.
Lock SHA-256: `1b7d690225a5ee1900d268df23766e92aa6951f541e018f7a65d950c18c66953`.
Elixir 1.20.3, OTP 29, Apple M1 Max, two schedulers, Mix dev.
