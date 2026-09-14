> Delivery seam prepared for the local Jido V3 beta candidate; release gates remain open.

# 99 — Delivery

## Briefing

The local Jido V3 candidate has one defined beta package set and four delivery
records. The package uses published Hex sources for `jido_action`,
`jido_signal`, and the optional Bedrock dependencies. Bedrock persistence is
included in the beta claim. All real Bedrock service tests are skipped while
upstream fixes are pending; the unproved contracts still block publication.

The candidate includes an explicit quiescent Agent Server upgrade boundary,
validated Agent definition migration, and additive local Topology target
updates. It does not claim arbitrary BEAM code pinning, Plugin runtime or
private Server-state migration, destructive Topology updates, Jido AI, Jido
Browser, a distributed control plane, or an OpenTelemetry bridge. These limits
have explicit dispositions in the scope ledger. Publication still needs a
human release decision and an exact-commit CI result.

## Boundary

- Owner: the Jido release owner and the cross-seam delivery record.
- Owns: release scope, package compatibility, local gates, evidence freshness,
  compatibility policy, migration limits, and the release decision input.
- Does not own: subsystem behavior, external integration packages, distribution
  policy, or publication authority.

## Current result

| Area | Result |
| --- | --- |
| Scope | Every prerequisite requirement range and every skip has a disposition. |
| Package set | Jido `3.0.0-beta.1`, Hex `jido_action 3.0.0-beta.11`, Hex `jido_signal 3.0.0-beta.4`, optional Hex Bedrock `0.7.2`, and Bedrock Raft `0.10.1`. |
| Plugin seam | Core contract tests cover the four owner facets. |
| Runtime floor | Elixir 1.18.5/OTP 27 fails while compiling an example Directive before core tests run. |
| Current runtime | Elixir 1.20.3 and OTP 29.0.5 pass quality, 92.4% core-only coverage, 240 examples, 523 authoring tests, seven benchmark tests, docs, and the full local suite with two skips. The service profile passes 53 tests with 33 Bedrock skips. MinIO passes 28 with one Bedrock skip on repeat; its prior run had one direct S3 Topology timeout. The skipped contracts remain unproved. |
| Authoring | 523 authoring tests pass; the larger case library remains future work. |
| Core exclusion | `DIST-03` remains excluded. The user directed a skip for `SYSTEM-CLUSTER-01`, which asserts the same out-of-scope cluster authority contract. |
| Hex package | Build, unpack inspection, fresh dependency resolution, production compile, and docs pass. The [CI Hex dry run](https://github.com/agentjido/jido/actions/runs/34876701594) passes on `c147595e`, before the skip; no upload occurred. |
| Publication | Not performed. Bedrock durability, support floor, exact-commit CI, and human approval remain open gates. |

## Example contract classification

| Class | Examples | Ownership |
| --- | --- | --- |
| Core capability | Agent observation, causal trace, durable scheduling, remote child placement, remote lifecycle, checkpoint identity, checkpoint portability, indeterminate writes, and bounded live upgrades | Jido provides and tests the behavior. |
| Application extension pattern | Recoverable delivery and pending-job recovery | Jido provides commit, persistence, Plugin runtime, and restart primitives. The application owns effect IDs, idempotency, approval, retry, and cancellation policy. |

## Records

- [Scope ledger](scope-ledger.md)
- [Package matrix](package-matrix.md)
- [Compatibility register](compatibility-register.md)
- [Evidence record](evidence.md)
- [Delivery design](design.md)
- [Delivery alignment](alignment.md)

## Dependencies

This seam closes after [00 Overview](../00_overview/alignment.md) through
[13 Observability](../13_observability/alignment.md), plus
[90 Package boundaries](../90_package-boundaries/alignment.md). The local result
is an input to CI and the human publication decision. It is not a publication.
