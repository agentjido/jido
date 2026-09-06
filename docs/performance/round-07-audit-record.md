# Round 07: Audit record ID defaults

Decision: **accepted**. Change: `ae9bfea6`.

`Audit.record/3` evaluated `ID.generate!()` before `Keyword.get/3`, including
when the caller supplied an ID. `Keyword.get_lazy/3` calls the generator only
when the key is absent. Supplied values, including `nil`, remain unchanged.

## Evidence

The fixture creates 100 records per timed call. It checks each field and checks
generated UUIDs. Setup, result checks, and cleanup are outside the time sample.
Resource samples use separate calls. The short profile has 30 time samples and
three resource samples per case, in each fresh VM. Pair order alternates.

Final five-pair results, candidate / baseline:

| Case | Median time | p95 time | Caller reductions | Observed process bytes | Copied result heap |
| --- | ---: | ---: | ---: | ---: | ---: |
| Supplied ID | 0.175 | 0.210 | 0.344 | 0.515 | 1.000 |
| Generated ID | 1.009 | 0.933 | 0.982 | 1.000 | 1.000 |

All five supplied-ID pairs had lower time, caller reductions, and observed
process bytes. This is about 82% less time and 48% less sampled process memory
for this batch. It is not a speed claim for all Jido operations. The returned
data has the same copied size. No helper processes remained after any case.

The generated-ID path stayed within the time and process-memory gates. Its
observed binary bytes ranged from 128 to 416 on the baseline and were 416 on the
candidate. The unchanged-code control also ranged from 128 to 416 bytes. Copied
results had zero receiver binary bytes on both sides. This small transient
binary variation is within the observed control range; it is not evidence of
retained memory growth. Sampled peaks are not exact peaks or allocation totals.

An earlier five-pair control had time ratios 0.995 for supplied IDs and 1.018
for generated IDs. An initial five-pair candidate run and a further ten-pair
confirmation run both had supplied-ID time ratios near 0.181 and process-byte
ratios near 0.515. Those runs used the tool before the untraced-task cleanup
check was added. They are separate evidence sets, not pooled with the final run.

## Reproduction

- Baseline: `4a00feb38d3c0536c7acca489a15cdc266fbffb6`.
- Candidate: `beaefe2bf33a1f785873ff5d00e48800b6ceb93a`.
- Baseline runtime SHA-256: `5f229afe4dbb654a61e0e11854627972a584736542aaad5c62b4e58758f08564`.
- Candidate runtime SHA-256: `ef820b829e0c07236e33a3f097411356a56315acbe1f002614592fe5a5a39fbd`.
- Tool SHA-256: `1e17fe878a82107a2dbe9f4209e9aa2464de525238297a885491538347c0b306`.
- Lock SHA-256: `1b7d690225a5ee1900d268df23766e92aa6951f541e018f7a65d950c18c66953`.
- Elixir 1.20.3, OTP 29, ERTS 17.0.5, Apple M1 Max, two schedulers, Mix `dev`.
- Local evidence: `bench/results/round-07-final/`, including the manifest,
  per-pair reports, command logs, and summary. Earlier runs are in
  `round-07-control`, `round-07-candidate`, and `round-07-confirmation`.

```sh
python3 bench/repeat.py --baseline ../jido_core_bench_base --candidate . \
  --profile short --filter audit/record --rounds 5 --output bench/results/round-07-rerun
```

## Checks

Tests cover supplied fields, a supplied `nil` ID, and UUID generation when the
ID is absent. Seven benchmark contract tests passed. All 124 short and 161 scale
cases passed their result, transfer, and cleanup checks. All 53 smoke cases also
passed on Elixir 1.18.5 / OTP 27.3.4.12.

Core selection: 888 passed, one existing DIST-03 exclusion, 83.4% core coverage.
Example selection: 272 passed and the same 11 existing research-example failures.
Examples do not enter the 80% core coverage gate. Format, compile with warnings
as errors, strict warning lint, Dialyzer, docs, and Hex package build passed.
