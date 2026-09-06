# Round 48: Scheduler delivery task capture

Decision: **accepted**.

The delivery task referenced two fields through the complete runtime map.
The change binds the server and previous-job values before it builds the task
function. Cron definitions, timer state, and options stay in the runtime.

Five fresh-VM pairs measured the actual runtime handler with an owned empty
Plugin-state reply fixture. It checks the idle result and removes the task,
timer, and reply process. It does not measure a complete Agent Server Turn.

| Payload | Time ratio | Faster pairs | p95 ratio | Caller reduction ratio | Sampled process-peak ratio |
| --- | ---: | ---: | ---: | ---: | ---: |
| small | 0.914 | 4/5 | 0.830 | 0.992 | 1.000 |
| large_map | 0.119 | 5/5 | 0.146 | 0.473 | 0.634 |
| large_binary | 0.936 | 4/5 | 0.993 | 0.992 | 1.000 |
| large_list | 0.221 | 5/5 | 0.252 | 0.439 | 0.703 |

The unchanged-code control time ratios ranged from 0.686 to 1.021. Binary
timing varied too much to claim a gain for that case. Control sampled process
peaks were unchanged. The large map and list time gains exceed this variation.
All copied result sizes were unchanged. No owned helper remained.

A separate diagnostic traces the function passed to `Task.async/1`, then
copies that function to a receiver. All five fresh-VM pairs returned these
same copied flat heap sizes:

| Payload | Before, bytes | After, bytes |
| --- | ---: | ---: |
| small | 1088 | 40 |
| large_map | 70784 | 40 |
| large_list | 81088 | 40 |
| large_binary | 1152 | 40 |

The candidate function no longer captures the runtime map. This is more than
99.9% less copied function heap for the large map and list cases. This is one
argument transfer, not all task traffic. Large binary contents can be shared;
the heap values do not count their full size. The traced probe supplies no
timing evidence. The time measurements ran separately without call tracing.

The 28 focused benchmark and scheduler tests passed. The new runtime test
checks the idle cursor, retained cron definitions, completed task removal,
cancelled timeout, and next pending timer. [Complete checks](phase-42-checks.md)
passed with 894 core tests and 83.5% core coverage. A minimum-version candidate
probe on Elixir 1.18.5 / OTP 27 returned 72 copied bytes for each function, with
no runtime map captured. This floor probe has no completed baseline pair and
supplies no cross-version timing comparison.

Evidence: `bench/results/round-48`, `round-48-control`, and `round-48-capture`.
Probe: `bench/capture_scheduler.exs`.

Baseline commit: `f71f842c0ad69bb00d398bf4d77c93b6b78edc43`.
Baseline runtime SHA-256: `d2c12025f34d3c55654fd9d80685eac096ef374bb6cff12343aa3b067d0d3447`.

Candidate commit: `1653102425f617e94e7880c57317a8189dd61e0d`.
Candidate runtime SHA-256: `e4ffb2d2aaf900b4d164ca9f7aded353eed1b80f75352b85a031462d00111da3`.

Tool SHA-256: `bfd05cd6c321cf40203fd064cd441ac89b5e92887e25b2281a68d4bf54da4283`.
Elixir 1.20.3, OTP 29, Apple M1 Max, two schedulers, Mix dev.
