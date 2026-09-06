# Round 06: Read normalization options once per batch

Decision: **rejected after measurement**. No runtime change was retained.

The trial resolved the ID generator once in `normalize_many/4` and passed it to
a private entry normalizer. Public single-entry normalization retained option
lookup. An empty batch returned immediately. ID order and default behavior
tests passed.

Baseline: `99b92e80`. Trial: `443aab71` (unpublished experiment, removed before
shipping). Five scale-profile pairs selected all Thread cases. Tool SHA-256:
`1e17fe878a82107a2dbe9f4209e9aa2464de525238297a885491538347c0b306`.
The runtime and lock matched Round 07. Local evidence, including full source
hashes and raw samples: `bench/results/round-06`.

| Case | Time ratio | Process-byte ratio | Lower-time pairs |
| --- | ---: | ---: | ---: |
| Normalize 100 | 0.940 | 1.000 | 5/5 |
| Normalize 1,000 | 0.942 | 1.000 | 5/5 |
| Normalize 10,000 | 0.973 | 0.724 | 5/5 |
| Append batch 100 | 0.940 | 1.000 | 5/5 |
| Append batch 1,000 | 0.946 | 1.000 | 5/5 |
| Append batch 10,000 | 0.892 | 1.000 | 5/5 |
| Append one to 10,000 | 0.989 | 1.618 | 5/5 |
| Last of 10,000 | 0.949 | 1.618 | 3/5 |
| Slice of 10,000 | 0.996 | 1.618 | 4/5 |

Larger normalization batches used about 7% fewer caller reductions. The
100- and 1,000-entry time gains were repeatable. However, sampled process memory
increased by about 62% in three large-history cases. Resource probes include
Thread construction during setup, so a normalization change can affect a
subsequent read case. The unchanged-code control had process-byte ratios of
1.000 for these cases. A small time gain does not justify this memory result.

Copied result sizes were unchanged. All result and process-cleanup checks
passed. These observations do not establish an allocation total or exact peak.
The original implementation remains in place.
