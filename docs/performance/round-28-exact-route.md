# Round 28: One exact route

Decision: **rejected**. The Router path remains in place.

The trial validated a matching single Route, then selected its target without
building a Router index. Wildcards, predicates, list targets, and other route
forms used the original path. The 124 focused Agent, authoring, schema, Server,
and benchmark tests passed. Tests cover matching invalid routes, target lists,
wildcards, predicate calls, route defaults, and custom callbacks.

Five fresh-VM pairs covered 65 Agent cases. Direct routing improved by about
9% for three single-route payloads, but not for the large-list payload. Complete
commands had no clear gain. Some common command and Flow sampled peaks grew
by 21% to 33%. The narrow routing gain does not justify these wider results.

| Selected case | Time ratio | Faster pairs | Sampled process-peak ratio |
| --- | ---: | ---: | ---: |
| prepare/routes_1/small | 1.031 | 2/5 | 1.000 |
| route/routes_1/small | 0.914 | 5/5 | 1.000 |
| cmd/routes_1/small | 1.064 | 1/5 | 1.013 |
| flow/routes_1/small | 1.029 | 2/5 | 1.331 |
| prepare/routes_1/large_map | 0.971 | 4/5 | 1.000 |
| route/routes_1/large_map | 0.908 | 5/5 | 1.000 |
| cmd/routes_1/large_map | 1.005 | 2/5 | 1.000 |
| prepare/routes_1/large_binary | 0.945 | 5/5 | 1.000 |
| route/routes_1/large_binary | 0.914 | 5/5 | 1.000 |
| cmd/routes_1/large_binary | 0.985 | 3/5 | 0.345 |
| prepare/routes_1/large_list | 0.981 | 3/5 | 1.000 |
| route/routes_1/large_list | 0.992 | 4/5 | 1.000 |
| cmd/routes_1/large_list | 0.986 | 4/5 | 1.000 |
| route/routes_16/small | 0.980 | 3/5 | 1.000 |
| cmd/routes_16/small | 0.977 | 3/5 | 1.303 |
| flow/routes_16/small | 0.996 | 4/5 | 1.213 |
| route/routes_16/large_map | 0.994 | 4/5 | 1.000 |
| route/routes_16/large_binary | 0.974 | 5/5 | 1.000 |
| route/routes_16/large_list | 0.989 | 4/5 | 1.000 |

The unchanged-code control single-route time ratios ranged from 1.000 to
1.023. Its small single-route command ratio was 1.054, so the candidate's
1.064 command ratio alone is not strong evidence of a speed regression. All
control process-byte ratios were 1.000. Sampled peaks include setup and cleanup;
they do not measure total allocation. No memory improvement is claimed.

No owned helper remained. The trial was removed from the unpublished local
history. Its exact runtime patch is `trials/round-28-exact-route.patch`. The
new contract tests remain. Runtime source again matches the checked and pushed
phase-43 version, so its complete checks still apply.

Evidence: `bench/results/round-28` and `round-28-control`.

Baseline commit: `5d476e88239f783dfab60d07c792b3adf65b786a`.
Runtime SHA-256: `18f5b64df277906515954cbb7540d4255c607fc994d667e60d4b3eb8da50cdf9`.

Trial commit: `6df427a3c3f525a6bf9f512b0518ae435afbfbe1`.
Runtime SHA-256: `6c1df1cbc4313fb7f714f42872e38ef0ceb528d41c3aaf3b912e908b64da74c9`.

Tool SHA-256: `e1917c543a4a7f4cac5441b13011807eb1fa7a90dd35c69e935b82afaefcbc60`.
Lock SHA-256: `1b7d690225a5ee1900d268df23766e92aa6951f541e018f7a65d950c18c66953`.
Elixir 1.20.3, OTP 29, Apple M1 Max, two schedulers, Mix dev.
