> Seam review entry point. This document is pending approval.

# 99 — Delivery

## Briefing

Jido is a local V3 beta candidate, not a release-ready package. The current
branch declares `3.0.0-beta.1`. It has a strong core test and quality setup,
public guides, migration material, examples, and past point-in-time check
results. It also has pending target contracts, 11 skipped research assertions,
one approved cluster-authority skip, local path dependencies, and no proved V3
ecosystem package set. The recommended delivery contract keeps code and
executable tests as canonical evidence. It requires the user to select the
release scope first. It then requires one traceable, commit-specific release
record for the selected package set. No old delivery plan or saved result text
counts as current proof.

## Why this seam exists

- Owner: the Jido release owner and the cross-seam delivery record.
- Owns: release scope, package compatibility, release gates, evidence
  freshness, compatibility and deprecation policy, migration proof, and the
  final release decision.
- Does not own: Agent or runtime behavior, package-specific implementation,
  exact public values, adapter behavior, ecosystem product policy, or a
  detailed implementation task plan.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Design approval | All prerequisite seam documents are pending approval. | The release scope names each required, deferred, or excluded requirement. |
| Core candidate | `3.0.0-beta.1` on `v3-spike`; publication checks are incomplete. | Package metadata, docs, migration text, and release notes describe one selected candidate. |
| Package set | Jido uses local `jido_action` beta.8 and Hex `jido_signal` beta.4. Jido AI uses local V3 paths. Jido Browser still selects V2 Jido packages. | One explicit, publishable package set passes public-only compile and integration tests. |
| Quality | `mix quality` covers format, compile, Credo, Dialyzer, and core tests. Other checks are separate. | One commit-specific record covers every required quality, docs, package, runtime, example, and migration gate. |
| Research | A current focused run has 34 passes and 11 documented skips. One core cluster-authority test is also skipped. | A skip remains only when its contract is explicitly outside the release scope and has an owner and reason. |
| Compatibility | V2 migration guides exist. Supported V3 APIs remain while owner seams propose additive changes. | One compatibility register defines support, deprecation, stored-data, upgrade, downgrade, and rollback rules. |
| Planning | Old delivery files mixed history, target changes, acceptance lists, and task order. | This seam states requirements and high-level gates. A later `ce-plan` artifact owns implementation tasks after approval. |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| No approved release scope | A passing core suite cannot decide which pending target contracts must ship. | A requirement-level release-scope ledger. | 00 through 13, 90, and 99 |
| No proved package set | Local paths and mixed V2/V3 consumers cannot support a publication claim. | A publishable V3 set with public-only integration proof. | 90 Package boundaries and 99 Delivery |
| Incomplete release evidence | Past results do not prove the current commit. | One fresh evidence record with commands, versions, commits, results, and exceptions. | 99 Delivery |
| Missing compatibility policy | Removal or stored-data change can break users without a controlled path. | Dated support, deprecation, migration, downgrade, and rollback rules. | Owner seams and 99 Delivery |
| Research skips need scope decisions | Skips preserve useful target assertions but do not prove a release contract. | Required assertions pass; deferred assertions stay named and non-blocking. | Owner seams and 99 Delivery |
| Documentation drift | Version, dependency, migration, example, and saved-result claims can disagree. | Checked public docs and examples for the selected candidate. | 02, 90, and 99 |

## Decisions requested

1. **Release scope:** Approve a ledger that marks every prerequisite seam
   requirement as required, deferred, or excluded for this release.
2. **Package set:** Decide whether the release claim covers only Jido,
   `jido_action`, and `jido_signal`, or also Jido AI and Jido Browser.
3. **Release roles:** Name the release owner, approval owner, compatibility
   owner, and gate-exception owner.
4. **Research skips:** Approve which named research contracts can remain
   deferred. A release-required assertion cannot stay skipped.
5. **Compatibility period:** Select a dated or version-bounded support period
   for retained APIs before any deprecation or removal.
6. **Upgrade scope:** Confirm that live Agent and live Topology upgrade are
   deferred, as the Overview recommends, or add them to the release gates.
7. **Stored data and rollback:** Select supported V2 import, V3 beta upgrade,
   downgrade, and rollback claims. State unsupported paths directly.
8. **Evidence freshness:** Approve one release record made from the exact
   candidate commit and package revisions, with no unrecorded working-tree
   changes.

## Dependencies

- Prerequisites: [00 Overview](../00_overview/alignment.md),
  [01 Agent](../01_agent/alignment.md),
  [02 Agent authoring](../02_agent-authoring/alignment.md),
  [03 Agent identity](../03_agent-identity/alignment.md),
  [04 Turn evaluation](../04_turn-evaluation/alignment.md),
  [05 Plugins](../05_plugins/alignment.md),
  [06 Commit and effects](../06_commit-and-effects/alignment.md),
  [07 Persistence](../07_persistence/alignment.md),
  [08 Agent Server](../08_agent-server/alignment.md),
  [09 Jido instance](../09_jido-instance/alignment.md),
  [10 Runtime topology](../10_runtime-topology/alignment.md),
  [11 Topology control plane](../11_topology-control-plane/alignment.md),
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md),
  [13 Observability](../13_observability/alignment.md), and
  [90 Package boundaries](../90_package-boundaries/alignment.md). All are
  pending approval.
- Dependents: release execution and any later implementation plans.
- Blockers: the eight decisions above, pending prerequisite approval, and the
  missing publishable package matrix.

## Documents

- [Target design](design.md)
- [Alignment plan](alignment.md)
