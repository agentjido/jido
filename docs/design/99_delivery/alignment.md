> Delivery alignment for the selected local beta scope; release gates remain open.

# Delivery alignment

## Status

- Alignment date: 2026-09-14.
- Candidate branch: `v3-spike`.
- Candidate identity: the commit that contains this record; code and test
  baseline `8d7e26c3`.
- Alignment state: `Prepared locally; Bedrock and local suite gates failing`.
- Package scope: Jido with its optional Bedrock adapter, plus the exact
  `jido_action`, `jido_signal`, Bedrock, and Bedrock Raft versions in the
  [package matrix](package-matrix.md).

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
| Persistence | Core record, compare-and-swap, tombstone, Plugin conversion, and restore tests pass. Strict Bedrock startup and MinIO-backed recovery do not. | `Blocked for beta` |
| Agent Server | Admission, execution, commit, Plugin runtime reconstruction, readiness, failure, settlement, quiescent upgrade, and validated definition migration pass. | `Proven` |
| Topology | Static local planning, Plugin contribution, activation, readiness, repair, and additive target update pass. | `Proven` |
| Errors and observation | The code registry is closed. Semantic lifecycle, Turn, persistence, and Topology events have bounded metadata and default consumers. | `Proven` |
| Package source | Production dependencies use published Hex packages. | `Proven` |
| Compatibility | No API is deprecated or removed. Stored-data, downgrade, rollback, and live-upgrade limits are explicit. | `Proven` |

## Delivery requirement disposition

| Requirements | State | Evidence or limit |
| --- | --- | --- |
| `DEL-REQ-001` to `DEL-REQ-007`, and `DEL-REQ-009` | `Proven` | Scope ledger and package matrix. |
| `DEL-REQ-010` to `DEL-REQ-012`, `DEL-REQ-014`, and `DEL-REQ-015` | `Proven locally` | Current `mix quality`, 92.4% core-only coverage, docs, seven benchmark tests, and 240 example tests pass on the preparation tree. Exact-commit verification remains open. |
| `DEL-REQ-013` and `DEL-REQ-017` | `Refresh required` | Package build and unpacked production compile pass, but the Hex publish dry run stops at authentication. The full local suite still fails. |
| `DEL-REQ-016` | `Failed` | Elixir 1.18.5/OTP 27 cannot compile the example Directive module, so core tests do not start. |
| `DEL-REQ-018` | `External gate` | Exact-commit CI needs a published remote commit. No local result claims this gate. |
| `DEL-REQ-019` and `DEL-REQ-020` | `Refresh required` | The preparation record names the current baseline. Final evidence must name one committed candidate and clean worktree. |
| `DEL-REQ-021` to `DEL-REQ-024` | `Open` | `DIST-03` is excluded by scope, but the enabled `SYSTEM-CLUSTER-01` probe still fails in the full local suite. The `:flaky` tag is not an exception. |
| `DEL-REQ-025` to `DEL-REQ-033` | `Refresh required` | Public Action-version text now matches beta.11 and docs build passes. Recheck the final candidate and Bedrock claim after the failing gates close. |
| `DEL-REQ-034` to `DEL-REQ-038` | `Bounded` | V2 import and downgrade are not claimed. Quiescent Agent upgrade, validated definition migration, and additive local Topology update have executable proof. The guide states the limits. |
| `DEL-REQ-039` | `Proven` | Public docs state that Jido cannot undo external work completed before a failed commit. |
| `DEL-REQ-040` | `Proven` | This seam contains gates and records, not a task backlog. |
| `DEL-REQ-041` and `DEL-REQ-042` | `Satisfied by execution` | The user directed implementation. Repository instructions did not permit use of a planning skill. Commits and records provide traceability. |
| `DEL-REQ-043` | `Blocked` | Bedrock is included in beta. Real Bedrock services and MinIO snapshot profiles fail on the selected Hex dependency set. |

## Remaining release gates

| Gate | Owner | Result needed |
| --- | --- | --- |
| Exact-commit CI | Jido release owner | The configured workflow passes for the candidate commit. |
| Bedrock beta profile | Bedrock and Jido release owners | A published Bedrock dependency set passes real service and MinIO snapshot profiles. |
| Local full suite | Jido release owner | Resolve the `SYSTEM-CLUSTER-01` gate while preserving the excluded cluster-authority scope. |
| Support floor | Jido release owner | Elixir 1.18/OTP 27 compiles the full test tree and passes the core suite. |
| Hex dry run | Jido release owner | Complete the dry run with approved release credentials; the unauthenticated package build already passes. |
| Release approval | Human release approver | Accept the scope, package matrix, compatibility register, and evidence record. |
| Publication | Human release approver | Publish only after the first two gates pass. |

These gates do not change the implemented local seam. They prevent this record
from claiming that a package was approved or published.

## Completion criteria

- [x] Every prerequisite requirement range and test skip has a disposition.
- [ ] Required beta contracts, including Bedrock, have passing executable evidence.
- [x] The package uses publishable production dependency sources.
- [x] Compatibility and migration limits are explicit.
- [x] Local quality, docs, and example gates pass on the preparation tree.
- [ ] Exact-commit quality, docs, and example evidence is recorded for the
      final candidate.
- [ ] Coverage, package, and runtime-matrix gates are refreshed for the final
      candidate. The current benchmark contract run passes.
- [ ] Bedrock services and MinIO snapshot profiles pass against the selected
      published dependency set.
- [ ] The local full-suite gate has a passing result or approved disposition.
- [ ] Exact-commit CI passes after the candidate commit is available remotely.
- [ ] A human release approver accepts and publishes the candidate.
