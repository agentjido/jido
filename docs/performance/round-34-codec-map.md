# Round 34: Codec document map scans

Decision: **accepted**, using direct map iteration.

The original map check built a list containing each key and value. The
accepted version checks pairs from a map iterator. It still checks every key
type before any value, then follows map enumeration order. Depth, node, string,
map, and list limits keep their original errors.

The first trial used `Enum.reduce_while/3`. It reduced scan time but increased
several sampled process peaks. It was replaced by direct iterator recursion.
Its patch is `trials/round-34-reducer.patch`; its evidence is `bench/results/round-34`.
The unpublished trial commit was `28c47c43`. No part of that trial remains.

## Paired time and resource results

Five fresh-VM short-profile pairs covered 22 codec cases. The following ratios
are candidate divided by baseline. Resource samples include setup and cleanup.

| Case | Time ratio | Faster pairs | p95 ratio | Sampled process-peak ratio |
| --- | ---: | ---: | ---: | ---: |
| encode/1 | 0.974 | 5/5 | 0.953 | 1.227 |
| decode/1 | 0.993 | 3/5 | 1.038 | 1.227 |
| encode/16 | 0.979 | 3/5 | 1.030 | 0.532 |
| decode/16 | 0.989 | 3/5 | 1.051 | 0.766 |
| generated/1 | 0.986 | 3/5 | 1.052 | 1.000 |
| generated/16 | 0.968 | 4/5 | 1.035 | 1.000 |
| check_map/0/scalar | 0.506 | 3/5 | 1.000 | 1.000 |
| check_map/0/nested | 0.506 | 5/5 | 1.000 | 1.000 |
| check_map/0/bad_key | 0.999 | 3/5 | 1.024 | 1.000 |
| check_map/0/bad_value | 1.000 | 1/5 | 0.977 | 1.000 |
| check_map/8/scalar | 0.357 | 5/5 | 0.666 | 0.702 |
| check_map/8/nested | 0.816 | 5/5 | 0.793 | 1.000 |
| check_map/8/bad_key | 0.947 | 4/5 | 0.900 | 1.000 |
| check_map/8/bad_value | 0.905 | 5/5 | 0.854 | 0.641 |
| check_map/1000/scalar | 0.759 | 5/5 | 0.702 | 1.499 |
| check_map/1000/nested | 0.837 | 5/5 | 0.750 | 0.540 |
| check_map/1000/bad_key | 1.000 | 2/5 | 1.111 | 1.000 |
| check_map/1000/bad_value | 0.742 | 5/5 | 0.739 | 1.499 |
| check_map/10000/scalar | 0.729 | 5/5 | 0.705 | 0.438 |
| check_map/10000/nested | 0.803 | 5/5 | 0.816 | 1.000 |
| check_map/10000/bad_key | 1.004 | 2/5 | 0.968 | 1.000 |
| check_map/10000/bad_value | 0.711 | 5/5 | 0.724 | 0.438 |

For valid 1,000- and 10,000-entry maps, time fell by 16% to 27% in every pair.
The complete encode/decode time changes were small and within control
variation; no complete-codec throughput gain is claimed. Empty-map samples
are near clock resolution and do not establish a useful time gain.

Unchanged-code control medians ranged from 0.920 to 1.049 for map checks, and
from 0.942 to 0.989 for complete codec cases. All control process-byte ratios
were 1.000. No owned helper remained. Valid copied values were unchanged;
successful map checks return the immediate atom `:ok`. Error stack traces
differ across compiled versions, so their lower copied sizes are not used as
evidence for this decision. Tests compare all error fields except stack traces.

Four cases had higher sampled peaks:

| Case | Before, bytes | After, bytes |
| --- | ---: | ---: |
| encode/1 | 21,512 | 26,400 |
| decode/1 | 21,512 | 26,400 |
| check_map/1000/scalar | 284,528 | 426,384 |
| check_map/1000/bad_value | 284,528 | 426,384 |

These increases remain part of the result. Lower allocation does not promise
a lower sampled peak in every workload. The 10,000-entry scalar and invalid-value
cases had 56% lower sampled peaks; the 1,000-entry nested case had 46% lower.

## Heap allocation follow-up

A separate OTP 29 `tprof` run measured caller heap allocation for 100 calls after
setup and warmup. The final result was checked. Five fresh-VM pairs alternated
order. Every pair returned the same byte totals shown below. This traced
diagnostic supplies no timing evidence and excludes initial process argument
transfer, setup, helper processes, and off-heap binary contents.

| Case / 100 calls | Before, heap bytes | After, heap bytes | Ratio |
| --- | ---: | ---: | ---: |
| encode/1 | 6,076,904 | 5,895,280 | 0.970 |
| decode/1 | 8,292,880 | 8,111,304 | 0.978 |
| check_map/1000/scalar | 24,009,952 | 13,608,360 | 0.567 |
| check_map/1000/nested | 62,409,688 | 40,007,984 | 0.641 |
| check_map/1000/bad_value | 23,177,344 | 12,718,288 | 0.549 |

The 1,000-entry map scans allocated 36% to 45% less caller heap. The two small
complete codec cases also allocated less. These allocation results and the
repeatable large-map time gains support acceptance despite the recorded peak
increases. Applications with strict peak limits should check their own map
sizes and call patterns.

The 149 focused codec, topology, Agent, and benchmark tests passed. Complete
[core, quality, and floor checks](phase-43-checks.md) passed with 898 core tests
and 83.5% core coverage.

Evidence: `bench/results/round-34-control`, `round-34-iterator`, and `round-34-heap`.
Allocation probe: `docs/performance/probes/round-34-heap.exs`.

Baseline commit: `0ae1e948fe1e2c28c24abdef50fb8ce3f48149fa`.
Runtime SHA-256: `e4ffb2d2aaf900b4d164ca9f7aded353eed1b80f75352b85a031462d00111da3`.

Candidate commit: `6e2b638e97dd142317782255cc9865620c0a4598`.
Runtime SHA-256: `18f5b64df277906515954cbb7540d4255c607fc994d667e60d4b3eb8da50cdf9`.

Tool SHA-256: `e1917c543a4a7f4cac5441b13011807eb1fa7a90dd35c69e935b82afaefcbc60`.
Lock SHA-256: `1b7d690225a5ee1900d268df23766e92aa6951f541e018f7a65d950c18c66953`.
Elixir 1.20.3, OTP 29, Apple M1 Max, two schedulers, Mix dev.
