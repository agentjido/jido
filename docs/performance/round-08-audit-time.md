# Round 08: Generate Audit timestamps only when absent

Decision: **passes the measurement gate; retained for combined checks**.

`Audit.record/3` now uses a lazy timestamp default. A caller-supplied timestamp,
including zero or nil, is preserved. An absent timestamp still reads the clock.
Five fresh-VM pairs used the short profile and the `audit/record` filter.

| Case (100 records) | Time ratio | p95 ratio | Caller reduction ratio | Process-byte ratio |
| --- | ---: | ---: | ---: | ---: |
| Supplied ID and time | 0.827 | 0.851 | 0.759 | 1.000 |
| Generated ID, supplied time | 0.958 | 0.901 | 0.924 | 1.000 |
| Supplied ID, default time | 0.997 | 1.007 | 1.000 | 1.000 |

All five supplied-ID/time pairs improved. Copied result heap size and process
cleanup were unchanged. The unchanged-code control time ratios were 1.009,
1.004, and 1.003 respectively. The 17% batch time reduction exceeds that control
variation. There is no sampled memory reduction claim for this round.

Tests cover default timestamp bounds, supplied nil and zero, generated IDs,
and buffer order. All 13 Audit and benchmark contract tests passed. The paired
result, transfer, and cleanup checks passed. Required combined checks remain
before this fix is pushed.

Local evidence: `bench/results/round-08`; control: `audit-expanded-control`.
The manifest and raw reports contain the complete environment and source data.

Baseline: `99b92e80ccdae21b63f02896cd81e1042c9d6e3b`.
Candidate: `58f8f9e374869754fa1b3b4fcbcc844416fb4c84`.

Baseline runtime SHA-256: `ef820b829e0c07236e33a3f097411356a56315acbe1f002614592fe5a5a39fbd`.
Candidate runtime SHA-256: `4f5d4fab1a38b4fc6f436530e063bdd965b82c365f1b4de3dfda49bb4fba3414`.
Tool SHA-256: `c7842333b5cbe48357e99c1b0100476b5ab177677b642570de066880243791f2`.
Lock SHA-256: `1b7d690225a5ee1900d268df23766e92aa6951f541e018f7a65d950c18c66953`.

Elixir 1.20.3, OTP 29, Apple M1 Max, two schedulers, Mix dev.
