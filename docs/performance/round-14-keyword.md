# Round 14: One keyword-list scan

Decision: **accepted**.

For nonempty right lists, `DeepMerge` tested whether the left list was a
keyword list twice. It now tests that once and uses the result to select the
same empty, keyword-merge, or replacement path. The recursive merge callback,
keyword ordering, duplicate handling, and struct replacement code stay.

Five fresh-VM short-profile pairs selected all 17 map and keyword merge cases.
The keyword cases use batches of 25 operations. Appending one new key improved
by about 17% at 8, 128, and 1,024 keys, in all five pairs. Replacing with a
non-keyword list improved by 35% to 50%, in all five pairs. The smaller gains
for last-key replacement and nested duplicates also repeated in all pairs.

The unchanged-code control medians were 0.999 to 1.026, except the 1,024-key
empty override at 1.078. No gain is claimed for that empty-override case.
The unchanged plain-map paths stayed within the control range.

| Case | Time ratio | Faster pairs | p95 ratio | Caller reduction ratio |
| --- | ---: | ---: | ---: | ---: |
| merge/1/empty_true | 1.000 | 0/5 | 1.000 | 1.000 |
| merge/1/empty_false | 1.000 | 0/5 | 1.336 | 1.000 |
| merge/1000/empty_true | 1.000 | 0/5 | 1.000 | 1.000 |
| merge/1000/empty_false | 0.986 | 4/5 | 0.894 | 1.000 |
| merge_keywords/8/empty/25 | 1.000 | 1/5 | 0.941 | 1.000 |
| merge_keywords/8/append/25 | 0.830 | 5/5 | 0.916 | 0.773 |
| merge_keywords/8/replace_last/25 | 0.951 | 5/5 | 0.946 | 0.893 |
| merge_keywords/8/non_keyword/25 | 0.650 | 5/5 | 0.708 | 0.638 |
| merge_keywords/128/empty/25 | 1.000 | 4/5 | 0.949 | 1.000 |
| merge_keywords/128/append/25 | 0.835 | 5/5 | 0.828 | 0.695 |
| merge_keywords/128/replace_last/25 | 0.936 | 5/5 | 1.000 | 0.869 |
| merge_keywords/128/non_keyword/25 | 0.512 | 5/5 | 0.497 | 0.515 |
| merge_keywords/1024/empty/25 | 0.945 | 4/5 | 0.893 | 1.000 |
| merge_keywords/1024/append/25 | 0.832 | 5/5 | 0.753 | 0.702 |
| merge_keywords/1024/replace_last/25 | 0.932 | 5/5 | 0.893 | 0.861 |
| merge_keywords/1024/non_keyword/25 | 0.505 | 5/5 | 0.504 | 0.502 |
| merge_keywords/duplicates/25 | 0.943 | 5/5 | 0.947 | 0.860 |

All sampled process-peak and copied-result ratios were 1.000. There were no
owned helper starts or remaining helpers. No memory reduction is claimed.
All 81 focused merge, Agent, budget, and benchmark tests passed. Each keyword
batch checks all 25 complete results, including nested maps, duplicate keys,
empty overrides, and non-keyword replacement.

The [complete checks](phase-36-checks.md) passed with 83.5% core coverage.
The same 11 known example failures remain outside that coverage gate.
Evidence: `bench/results/round-14` and `round-14-control`.

Baseline commit: `13d48c40139b5e66b647db354b2e701f637312b1`.
Runtime SHA-256: `9452e74af75139d30d4a781976b8410f5c491dbbc9a727ddf38b185693dcc82e`.

Candidate commit: `598626a410c492287e654ecd48d911c25500f68b`.
Runtime SHA-256: `5ee487bd5c22eff08aaeb516de5bfdaa5f953d5c36d214f8e26b35b1bea842d4`.

Tool SHA-256: `4c6af3984b0bea872be2d77ce781b6d515230f0240615c54a47843a6be265d1b`.
Lock SHA-256: `1b7d690225a5ee1900d268df23766e92aa6951f541e018f7a65d950c18c66953`.
Elixir 1.20.3, OTP 29, Apple M1 Max, two schedulers, Mix dev.
