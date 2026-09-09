> Delivery seam selected and implemented for the local Jido V3 core candidate.

# 99 — Delivery

## Briefing

The local Jido V3 candidate has one defined core package set, one public-only
consumer, and four delivery records. The package uses published Hex sources for
`jido_action` and `jido_signal`. The consumer proves the public Plugin facets for
Agents, Agent Servers, persistence, and Topology together with Signal, Agent Ref,
durable storage, and instance operations.

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
| Package set | Jido `3.0.0-beta.1`, `jido_action 3.0.0-beta.9`, and `jido_signal 3.0.0-beta.4`. |
| Plugin seam | The public package consumer uses the four owner facets without private Jido APIs. |
| Runtime floor | The Elixir 1.18.5 and OTP 27.3.4.12 result is from the prior candidate and needs a release refresh. |
| Current runtime | Elixir 1.20.3 and OTP 29.0.5 pass the current quality, example, research, and documentation gates. |
| Research | 48 checks pass. No research check is skipped. |
| Core exclusion | `DIST-03` remains excluded because core does not claim cluster-exclusive ownership. |
| Publication | Not performed. Exact-commit CI and human approval remain external gates. |

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
