# Delivery scope ledger

This ledger applies to the local Jido `3.0.0-beta.1` core candidate. It uses
closed requirement ranges. Thus, it gives every prerequisite requirement ID a
disposition without copying each ID to a separate row.

## Authority

| Role | Owner |
| --- | --- |
| Delivery and compatibility owner | Jido maintainers |
| Evidence owner | The candidate commit and its author |
| Gate-exception owner | Human release approver |
| Publication approval owner | Human release approver |

No gate exception is approved. A deferred or excluded feature is a scope limit,
not a gate exception. A failing release gate remains a blocker.

## Requirement ranges

| Seam | Required | Deferred | Excluded |
| --- | --- | --- | --- |
| 00 Overview | `OVR-REQ-001` to `OVR-REQ-066` | None | None |
| 01 Agent | `AGT-REQ-001` to `AGT-REQ-041` | None | None |
| 02 Agent authoring | `AUTH-REQ-001` to `AUTH-REQ-062` | None | None |
| 03 Agent identity | `ID-REQ-001` to `ID-REQ-020`; `ID-REQ-023` to `ID-REQ-028` | `ID-REQ-021`, `ID-REQ-022` | None |
| 04 Turn evaluation | `TURN-REQ-001` to `TURN-REQ-044` | None | None |
| 05 Plugins | `PLG-REQ-001` to `PLG-REQ-076` | None | None |
| 06 Commit and effects | `COMMIT-REQ-001` to `COMMIT-REQ-044` | None | None |
| 07 Persistence | `PERS-REQ-001` to `PERS-REQ-051` | None | None |
| 08 Agent Server | `SRV-REQ-001` to `SRV-REQ-076` | None | None |
| 09 Jido instance | `INST-REQ-001` to `INST-REQ-056` | None | None |
| 10 Runtime topology | `RT-REQ-001` to `RT-REQ-051` | None | None |
| 11 Topology control plane | `TOP-REQ-001`; `TOP-REQ-003` to `TOP-REQ-005`; `TOP-REQ-059`, `TOP-REQ-060`; `TOP-REQ-062` to `TOP-REQ-076` | `TOP-REQ-006` to `TOP-REQ-058`; `TOP-REQ-061` | `TOP-REQ-002` is retired by its owner design. |
| 12 Errors and contracts | `ERR-REQ-001` to `ERR-REQ-018`; `ERR-REQ-020` to `ERR-REQ-024` | None | `ERR-REQ-019` is retired by its owner design. |
| 13 Observability | `OBS-REQ-001` to `OBS-REQ-020`; `OBS-REQ-022` to `OBS-REQ-043`; `OBS-REQ-046`; `OBS-REQ-048` to `OBS-REQ-054`; `OBS-REQ-056`, `OBS-REQ-057` | `OBS-REQ-021`; `OBS-REQ-044`, `OBS-REQ-045`, `OBS-REQ-047`, `OBS-REQ-055` | None |
| 90 Package boundaries | `PKG-REQ-001` to `PKG-REQ-005`; `PKG-REQ-007` to `PKG-REQ-030`; `PKG-REQ-034` to `PKG-REQ-038` | `PKG-REQ-031`, `PKG-REQ-032`, `PKG-REQ-039` | `PKG-REQ-006`, `PKG-REQ-033` for this core-only claim |

## Deferred and excluded effects

| Scope ID | Status | Owner | Reason and user effect | Review point |
| --- | --- | --- | --- | --- |
| `SCOPE-DIST` | Deferred | Future distributed control-plane owner | Core has no membership, automatic placement, lease, fencing, failover, or operator control plane. Static local Topology stays available. | Review with a public external package and its conformance suite. |
| `SCOPE-OTEL` | Deferred | Host integration owner | Core emits semantic Telemetry but does not include an OpenTelemetry SDK or bridge. | Review when a host bridge has disabled and in-memory SDK proof. |
| `SCOPE-TRANSPORT` | Deferred | Future transport owner | Core does not claim a general transport package or durable fabric API. Public Signal input remains available. | Review with a named package and transport contract tests. |
| `SCOPE-REF-DELIVERY` | Deferred | Future transport and placement owners | Local Ref resolution is implemented. Core does not claim Ref-addressed transport or automatic placement across nodes. | Review with replaceable-handle delivery and Ref-preserving placement tests. |
| `SCOPE-AI-BROWSER` | Excluded | Jido AI and Jido Browser owners | This package result does not claim V3 compatibility for AI or Browser. Core remains usable without either package. | Each package adds its exact matrix and compatibility tests. |
| `SCOPE-ERR-019` | Excluded | Errors seam | The proposed error projection version 2 was retired. Version 1 remains the contract. | Review only with a new versioned error design. |

## Bedrock beta gate

`Jido.Persistence.Bedrock` is included in this beta, not deferred or excluded.
The release requires passing `mix test.services` and the separate MinIO
snapshot profile against the exact published Bedrock dependency set in the
[package matrix](package-matrix.md). The current failures in
`SYSTEM-BEDROCK-01`, `SYSTEM-BEDROCK-04`, and `SYSTEM-BEDROCK-05`, plus the
native snapshot upload error recorded by `SYSTEM-BEDROCK-03`, block that gate.
Local, unpublished Bedrock patches do not close it.

## Skip classification

| Assertion | Status | Owner | Reason and user effect | Review point |
| --- | --- | --- | --- | --- |
| `DIST-03` | Excluded | Future distributed authority owner | Core does not guarantee one live owner across a cluster. Applications that need this must supply fenced external authority. | Review with enforceable epochs at every protected commit. |

`SYSTEM-CLUSTER-01` is a second, enabled probe of the same excluded cluster
authority contract. It currently fails in `mix test.all`; the `:flaky` tag is
not a release exception or proof of an intermittent fault. The release owner
must resolve the gate disposition before publication.

UP-01, UP-02, and UP-07 are implemented and are release-required evidence.
Their assertions pass without skip tags.

## Example contract classification

| Contract | Status | Owner and limit |
| --- | --- | --- |
| OBS-01, OBS-02, REC-03, DIST-01, DIST-02, PERSIST-01, PERSIST-02, PERSIST-03, UP-01, UP-02, and UP-07 | Core capability | Jido owns the bounded behavior proved by core and example tests. |
| REC-01 recoverable delivery | Application extension pattern | Core commits and restores Plugin intent. The application owns stable effect IDs, sink idempotency, retry interval, and retention. |
| REC-02 pending-job recovery | Application extension pattern | Core restores approved state and owned runtimes. The application owns approval, attempt identity, retry, and cancellation policy. |
