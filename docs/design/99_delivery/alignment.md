> Delivery alignment implemented for the selected local core scope.

# Delivery alignment

## Status

- Alignment date: 2026-09-09.
- Candidate branch: `v3-spike`.
- Candidate identity: the commit that contains this record, with parent
  `84dc2dc9`.
- Alignment state: `Implemented locally; external release approval pending`.
- Package scope: Jido, `jido_action`, and `jido_signal` only.

The [scope ledger](scope-ledger.md) is the source of truth for required,
deferred, and excluded work. The [evidence record](evidence.md) is the source of
truth for the local gate results. Executable tests remain canonical when saved
text and code differ.

## Implemented alignment

| Delivery area | Evidence | State |
| --- | --- | --- |
| Four-module Plugin seam | `Jido.Agent.Plugin`, `Jido.AgentServer.Plugin`, `Jido.Persistence.Plugin`, and `Jido.Topology.Plugin` have separate contracts and one package manifest. | `Proven` |
| Agent identity | Public Agent Ref construction, serialization, local resolution, persistence identity, and facade operations pass. | `Proven` |
| Turn and commit | Source-Signal selection is fixed, write authority fails closed, and execution-only context does not enter post-commit Directive work. | `Proven` |
| Persistence | Versioned records, initial writes, compare-and-swap, tombstones, collision checks, Plugin conversion, and restore pass. | `Proven` |
| Agent Server | Admission, execution, commit, Plugin runtime reconstruction, readiness, failure, settlement, quiescent upgrade, and validated definition migration pass. | `Proven` |
| Topology | Static local planning, Plugin contribution, activation, readiness, repair, and additive target update pass. | `Proven` |
| Errors and observation | The code registry is closed. Semantic lifecycle, Turn, persistence, and Topology events have bounded metadata and default consumers. | `Proven` |
| Package source | Production dependencies use published Hex packages. The unpacked Jido candidate passes a separate public consumer. | `Proven` |
| Compatibility | No API is deprecated or removed. Stored-data, downgrade, rollback, and live-upgrade limits are explicit. | `Proven` |

## Delivery requirement disposition

| Requirements | State | Evidence or limit |
| --- | --- | --- |
| `DEL-REQ-001` to `DEL-REQ-009` | `Proven` | Scope ledger, package matrix, and public consumer. |
| `DEL-REQ-010` to `DEL-REQ-017` | `Proven locally` | Quality, coverage, docs, package, benchmark, example, and two-runtime results. |
| `DEL-REQ-018` | `External gate` | Exact-commit CI needs a published remote commit. No local result claims this gate. |
| `DEL-REQ-019` and `DEL-REQ-020` | `Proven` | Evidence is bound to the containing commit and its recorded parent. |
| `DEL-REQ-021` to `DEL-REQ-024` | `Proven` | UP-01, UP-02, and UP-07 pass. `DIST-03` is the only excluded assertion and keeps its ID and reason. |
| `DEL-REQ-025` to `DEL-REQ-033` | `Proven` | Public guides, package metadata, examples, and the compatibility register agree. |
| `DEL-REQ-034` to `DEL-REQ-038` | `Bounded` | V2 import and downgrade are not claimed. Quiescent Agent upgrade, validated definition migration, and additive local Topology update have executable proof. The guide states the limits. |
| `DEL-REQ-039` | `Proven` | Public docs state that Jido cannot undo external work completed before a failed commit. |
| `DEL-REQ-040` | `Proven` | This seam contains gates and records, not a task backlog. |
| `DEL-REQ-041` and `DEL-REQ-042` | `Satisfied by execution` | The user directed implementation. Repository instructions did not permit use of a planning skill. Commits and records provide traceability. |

## Remaining external gates

| Gate | Owner | Result needed |
| --- | --- | --- |
| Exact-commit CI | Jido release owner | The configured workflow passes for the candidate commit. |
| Release approval | Human release approver | Accept the scope, package matrix, compatibility register, and evidence record. |
| Publication | Human release approver | Publish only after the first two gates pass. |

These gates do not change the implemented local seam. They prevent this record
from claiming that a package was approved or published.

## Completion criteria

- [x] Every prerequisite requirement range and test skip has a disposition.
- [x] Required core contracts have executable evidence.
- [x] The package uses publishable production dependency sources.
- [x] A separate public-only package consumer passes.
- [x] Compatibility and migration limits are explicit.
- [x] Local quality, coverage, docs, package, benchmark, example, and runtime
      gates pass.
- [ ] Exact-commit CI passes after the candidate commit is available remotely.
- [ ] A human release approver accepts and publishes the candidate.
