# Round 09: Empty Audit buffer updates

Decision: **passes the measurement gate; retained for combined checks**.

An empty update now counts the existing records once. It returns the current
state when within the limit. If the state exceeds the limit, it drops the excess
prefix using that count. Invalid limits still raise before either path.

Five fresh-VM pairs selected all nine Audit update cases with the short profile.
All result, transfer, and cleanup checks passed. Ratios are candidate / baseline.

| Case | Time | p95 | Caller reductions | Observed process bytes |
| --- | ---: | ---: | ---: | ---: |
| audit/update/1000/0 | 0.517 | 0.460 | 0.658 | 1.000 |
| audit/update/1100/0 | 0.547 | 0.546 | 0.825 | 1.000 |

Both large empty-update cases improved in all five pairs. Copied output size was
unchanged. The other update cases stayed within 3.1% on median time and had no
sampled process-memory increase. The one-record case is close to the clock's
resolution and is not used for a speed claim. The larger cases have 150 time
samples across five VMs per side, with gains well above control variation.

The first trial used `Enum.take/2` after the explicit count when the buffer was
too large. Reusing the count with `Enum.drop/2` removed that second size scan.
`round-09` holds the first trial; `round-09-final` is the acceptance evidence.
`audit-expanded-control` holds the unchanged-code control. All 13 Audit and
benchmark contract tests passed. Combined checks remain before push.

Baseline: `58f8f9e374869754fa1b3b4fcbcc844416fb4c84`.
Candidate: `b4b8c1d335bfe52296e04101dedd754402752115`.

Baseline runtime SHA-256: `4f5d4fab1a38b4fc6f436530e063bdd965b82c365f1b4de3dfda49bb4fba3414`.
Candidate runtime SHA-256: `f808afbd20ec04e8f9e8d65a9c2ac2d02845823b613bd0d4314f12c969049196`.
Tool SHA-256: `c7842333b5cbe48357e99c1b0100476b5ab177677b642570de066880243791f2`.
Lock SHA-256: `1b7d690225a5ee1900d268df23766e92aa6951f541e018f7a65d950c18c66953`.

Elixir 1.20.3, OTP 29, Apple M1 Max, two schedulers, Mix dev.
