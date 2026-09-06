# Rejected runtime trials

These patches preserve the rejected candidates without adding them to the
shipping runtime history. Apply a patch only in a separate checkout of its base.
Use `git apply --unidiff-zero PATH` because the patches omit context lines.
They change runtime source only; use the benchmark method and conditions from
the related round report. Raw measurements remain in local `bench/results`.

| Patch | Base | Trial identifier |
| --- | --- | --- |
| [01-indexed.patch](01-indexed.patch) | `4a00feb3` | `af77ec83` |
| [01-direct.patch](01-direct.patch) | `4a00feb3` | `9b12dd94` |
| [01-tail.patch](01-tail.patch) | `4a00feb3` | `d4b1d268` |
| [02-count.patch](02-count.patch) | `99b92e80` | `2f1a4681` |
| [06-options.patch](06-options.patch) | `916b010b` | `443aab71` |
| [10-prefix.patch](10-prefix.patch) | `b4b8c1d3` | `bedabf2e` |
| [11-full.patch](11-full.patch) | `869626ac` | `79bc0af2` |
| [11-reuse.patch](11-reuse.patch) | `869626ac` | `f24d6590` |
