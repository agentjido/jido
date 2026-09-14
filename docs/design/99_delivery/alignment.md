> Delivery alignment for the approved beta.1 scope; two beta-only gate exceptions are recorded.

# Delivery alignment

## Status

- Alignment date: 2026-09-14.
- Candidate branch: `release/v3`.
- Candidate identity: source baseline `4835d71a`; the final release workflow
  must verify the commit that contains this documentation record.
- Alignment state: `Approved for beta.1 with Bedrock and support-floor
  exceptions; final release workflow pending`.
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
| Persistence | Core record, compare-and-swap, tombstone, Plugin conversion, and restore tests pass. Strict Bedrock startup and MinIO-backed recovery remain unverified. | `Beta.1 exception` |
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
| `DEL-REQ-013` | `Proven for the CI source commit` | Package build, unpack inspection, fresh production compile, and CI Hex dry run pass on package-equivalent source. Final-candidate verification remains open. |
| `DEL-REQ-017` | `Proven locally with skip` | The full local suite passes: 2,015 passed, 2 skipped, 115 excluded, 93.5% coverage. The user directed the `SYSTEM-CLUSTER-01` skip for an excluded contract. |
| `DEL-REQ-016` | `Failed` | Elixir 1.18.5/OTP 27 cannot compile the example Directive module, so core tests do not start. |
| `DEL-REQ-018` | `Source baseline passed` | Release preflight [34882608048](https://github.com/agentjido/jido/actions/runs/34882608048) passed on `4835d71a`. The final documentation commit still needs the release workflow check. |
| `DEL-REQ-019` and `DEL-REQ-020` | `Refresh required` | The preparation record names the current baseline. Final evidence must name one committed candidate and clean worktree. |
| `DEL-REQ-021` to `DEL-REQ-024` | `Bounded` | `DIST-03` and `SYSTEM-CLUSTER-01` are excluded from normal runs. The user explicitly directed the system-probe skip; this is not proof of cluster authority. |
| `DEL-REQ-025` to `DEL-REQ-033` | `Refresh required` | Public Action-version text now matches beta.11 and docs build passes. Recheck the final candidate and Bedrock claim after the failing gates close. |
| `DEL-REQ-034` to `DEL-REQ-038` | `Bounded` | V2 import and downgrade are not claimed. Quiescent Agent upgrade, validated definition migration, and additive local Topology update have executable proof. The guide states the limits. |
| `DEL-REQ-039` | `Proven` | Public docs state that Jido cannot undo external work completed before a failed commit. |
| `DEL-REQ-040` | `Proven` | This seam contains gates and records, not a task backlog. |
| `DEL-REQ-041` and `DEL-REQ-042` | `Satisfied by execution` | The user directed implementation. Repository instructions did not permit use of a planning skill. Commits and records provide traceability. |
| `DEL-REQ-043` | `Beta.1 exception` | Bedrock is included in beta. All 33 real Bedrock service tests and the MinIO snapshot test are skipped. `BETA1-BEDROCK` permits this beta, but does not prove strict startup or snapshot recovery. |

## Remaining release gates

| Gate | Owner | Result needed |
| --- | --- | --- |
| Exact-commit CI | Jido release owner | The configured workflow passes for the candidate commit. |
| Bedrock beta profile | Bedrock and Jido release owners | `BETA1-BEDROCK` permits beta.1 only. Re-enable and pass the currently skipped strict, shutdown, and snapshot tests before the next release. |
| Support floor | Jido release owner | `BETA1-FLOOR` permits beta.1 only. Make Elixir 1.18/OTP 27 pass or narrow the declared range before the next release. |
| Hex dry run | Jido release owner | The CI dry run passes on `c147595e`, before the skip; rerun on the final candidate before release. |
| Release approval | Human release approver | Approved on 2026-09-14 with the two named beta.1 exceptions. |
| Publication | Human release approver | Publish only after the final candidate passes the release workflow. |

These exceptions do not change the implemented local seam. They do not convert
failed or skipped checks into passing evidence.

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
- [x] The local full-suite gate passes with the user-directed cluster-probe skip.
- [ ] Exact-commit CI passes after the candidate commit is available remotely.
- [x] A human release approver accepts the candidate with two beta.1-only exceptions.
- [ ] The release workflow publishes the approved candidate.
