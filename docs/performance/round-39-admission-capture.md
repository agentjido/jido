# Round 39: Admission task function capture

Decision: **accepted**.

`start_admission_task/2` used `data.plugin_specs` inside the task function.
The function therefore captured the full Server state. The command already
contained the Agent state, so the argument carried a second complete Agent
inside the Server state. The new code reads Plugin specs before constructing
the function. Callback order, runtime references, command data, timers, and
error handling stay the same.

## Evidence

Five fresh-VM short-profile pairs selected `server/admit`. An unchanged-code
control used the same scripts, environment, and settings. Its time ratios ranged
from 0.986 to 1.014 by case, and all process-byte ratios were 1.000.

A separate diagnostic captured the actual function argument passed to
`Task.Supervisor.async/2`. It copied that function to a receiver and checked the
receiver's flat heap size. Five more alternating pairs checked all four payloads.
Every baseline function captured Server state; no candidate function did.
Each payload's copied sizes were identical across all five pairs.

| Payload | Time ratio | p95 ratio | Before function bytes | After function bytes | Process-peak ratio |
| --- | ---: | ---: | ---: | ---: | ---: |
| small | 0.958 | 0.896 | 8,592 | 2,944 | 1.000 |
| large_map | 0.955 | 0.907 | 147,984 | 72,640 | 1.000 |
| large_list | 0.938 | 0.929 | 168,592 | 82,944 | 1.000 |
| large_binary | 0.948 | 0.839 | 8,720 | 3,008 | 0.956 |

All time cases improved in at least four of five pairs. The large-list case
improved by about 6%, above the unchanged-code control variation. The copied
function heap fell by about 51% for large maps and lists and 66% for small
state. This is one task-argument transfer, not all task traffic or total process
memory. The 1 MiB binary payload remained shared on both sides. Most sampled
process peaks did not change. Returned Agent size was unchanged. Caller reductions and observed shared
binary bytes were also unchanged. Each traced resource case started 11 owned
processes, including setup, and left zero owned processes. Median GC counts
were 63 to 58 for small state, 22 to 22 for maps, 20 to 20 for lists, and 120
to 121 for the binary fixture. These counts include setup and checks.
Observed helper reductions decreased slightly; they are lower bounds and do
not support a separate total-reduction claim.

All 89 focused Server, Plugin runtime, context, and benchmark tests passed.
Every timed, resource, and copy call checked its result and process cleanup.
The complete core selection passed: 890 tests, one existing DIST-03 exclusion,
and 83.5% core coverage. The example selection had 272 passes and the same 11
known research-example failures. Examples remain outside the 80% coverage gate.
Format, compile with warnings as errors, strict warning lint, Dialyzer, docs,
and package checks passed.

All 72 smoke cases and all four task-capture cases passed on Elixir 1.18.5 /
OTP 27.3.4.12. None of the floor captures held the complete Server state. This
was a compatibility run; its timings are not used for performance claims.

Local evidence: `bench/results/round-39`, `round-39-control`, and
`round-39-captures`. The copy diagnostic is `bench/capture_admission.exs`.
Its traced calls supply no timing evidence; time samples come from the separate
untraced benchmark runs.

Baseline: `9bb4c2bb85c08f4009e71fb342c609865ef701a9`.
Candidate: `b7e70606a80c75b58d0714e70ce566f2f99e8c23`.

Baseline runtime SHA-256: `f808afbd20ec04e8f9e8d65a9c2ac2d02845823b613bd0d4314f12c969049196`.
Candidate runtime SHA-256: `4b7d9b1cd998aeae8814157157590586523deb38e318aa8d50bae9168dac5eb4`.
Tool SHA-256: `2c9090866787aece532c594911bbb9639bd17a58d28f993fd511b6f265816c14`.
Lock SHA-256: `1b7d690225a5ee1900d268df23766e92aa6951f541e018f7a65d950c18c66953`.

Elixir 1.20.3, OTP 29, Apple M1 Max, two schedulers, Mix dev.
