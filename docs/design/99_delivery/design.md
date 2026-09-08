> Target seam design. This document is pending approval.

# Delivery design

## Scope and owner

- Owner: the Jido release owner and the cross-seam delivery record.
- In scope: release-scope selection, compatible package sets, release gates,
  evidence, public documentation, examples, migration, compatibility,
  deprecation, versioning, upgrade, downgrade, rollback, and release approval.
- Out of scope: subsystem behavior, package implementation details, product
  policy, and detailed implementation tasks.

This design specifies the release decision process. It does not approve a
target contract in another seam and does not assert that a current check
passes.

## Model

Delivery uses four records:

1. A **scope ledger** maps every prerequisite requirement to `required`,
   `deferred`, or `excluded`, with an owner and reason.
2. A **package matrix** names exact package versions, source types, commits or
   checksums, supported Elixir and OTP versions, and public integration tests.
3. A **compatibility register** names supported APIs and data, deprecations,
   removals, migrations, downgrade limits, rollback points, and support end.
4. An **evidence record** binds commands and results to one candidate commit,
   one clean or fully recorded worktree, and one package matrix.

A release can proceed only when every required requirement has current proof,
every allowed exception is recorded, and the approval owner accepts the same
records.

## Requirements

### Scope and authority

`DEL-REQ-001`: When a release candidate is prepared for final verification,
the delivery owner shall record every prerequisite seam requirement as
`required`, `deferred`, or `excluded` for that candidate.

`DEL-REQ-002`: When the delivery owner marks a requirement as `deferred` or
`excluded`, the scope ledger shall record its owner, reason, user effect, and
planned review point.

`DEL-REQ-003`: When a release gate has an exception, the gate-exception owner
shall record the gate, reason, risk, expiry, and approval identity.

`DEL-REQ-004`: When final release approval is requested, the release record
shall name the release owner, approval owner, compatibility owner, and
gate-exception owner.

### Compatible package set

`DEL-REQ-005`: When Jido claims V3 compatibility, the package matrix shall name
the exact Jido, `jido_action`, and `jido_signal` versions and sources.

`DEL-REQ-006`: Where a release claim includes Jido AI, Jido Browser, or another
integration package, the package matrix shall name its exact version and
source.

`DEL-REQ-007`: When the Jido package is prepared for publication, the Jido
package shall use publishable dependency sources, unless the approval owner
records a release-source exception.

`DEL-REQ-008`: When the selected package set is tested, a public-only consumer
fixture shall compile and run without private Jido modules, messages, process
names, or repository-only paths.

`DEL-REQ-009`: When a package matrix result is recorded, the evidence record
shall include each package commit or immutable package checksum.

### Quality gates and evidence

`DEL-REQ-010`: When release approval is requested, the release owner shall
record a passing `mix quality` result from the exact Jido candidate commit.

`DEL-REQ-011`: When release approval is requested, the release owner shall
record core coverage of at least 90 percent from `mix test --cover test/jido
--include flaky --seed 0` without new coverage exclusions.

`DEL-REQ-012`: When release approval is requested, the release owner shall
record a passing `mix docs --no-open -f html --warnings-as-errors` result.

`DEL-REQ-013`: When release approval is requested, the release owner shall
record a passing `mix hex.build` result and inspect the package contents for
required and excluded files.

`DEL-REQ-014`: When release approval is requested, the release owner shall
record a passing `mix benchmarks --seed 0` contract result.

`DEL-REQ-015`: When release approval is requested, the release owner shall
record a completed `mix examples --seed 0` result with each skip classified by
the scope ledger.

`DEL-REQ-016`: When release approval is requested, the release owner shall
record the core suite result on Elixir 1.18 and OTP 27.

`DEL-REQ-017`: Where the package claims support for another Elixir or OTP
combination, the release owner shall record the core suite result on that
combination.

`DEL-REQ-018`: When CI is a release gate, the release record shall identify the
workflow revision and the successful run for the exact candidate commit.

`DEL-REQ-019`: When a gate result is recorded, the evidence record shall store
the command, date, runtime versions, candidate commit, package matrix, result,
and applicable exception IDs.

`DEL-REQ-020`: If the candidate worktree has changes outside the candidate
commit, then the release owner shall either remove them from the verification
environment or record their exact diff in the evidence record.

### Tests and allowed research skips

`DEL-REQ-021`: If a skipped test maps to a release-required requirement, then
the release owner shall block release approval.

`DEL-REQ-022`: Where a research requirement is deferred or excluded, its
executable assertion may remain skipped only while the test has a requirement
identifier and a nonempty skip reason.

`DEL-REQ-023`: Where cluster-exclusive authority remains outside Jido core,
the `DIST-03` assertion may remain skipped only while the scope ledger records
that exclusion.

`DEL-REQ-024`: When a skipped research assertion becomes required, its owner
seam shall replace the skip with passing acceptance evidence before release.

### Documentation and examples

`DEL-REQ-025`: When release approval is requested, the documentation gate shall
confirm that the package version, dependency versions, support floor, and
publication state agree in package metadata, README, migration guides, and
installation examples.

`DEL-REQ-026`: When release approval is requested, the documentation gate shall
confirm that every public API retained, changed, deprecated, removed, or
deferred by the compatibility register has matching module or guide text.

`DEL-REQ-027`: When release approval is requested, the release owner shall run
a selected set of public examples for each release-required Agent, live
runtime, persistence, Plugin, Topology, and observation contract.

`DEL-REQ-028`: If saved result text disagrees with executable tests or current
automation, then the delivery record shall mark the text historical and use
the executable result as current evidence.

### Compatibility, versioning, and deprecation

`DEL-REQ-029`: When a supported V3 API is proposed to change, the compatibility
owner shall record its current form, replacement, support interval, warning
behavior, and removal gate.

`DEL-REQ-030`: While a supported API has no approved removal gate, Jido shall
keep that API available for the release candidate.

`DEL-REQ-031`: When a breaking public API or stored-data change is prepared for
release, the package version and release notes shall identify the break and its
migration path.

`DEL-REQ-032`: When package metadata selects a release version, the README,
documentation source reference, migration guide, and dependency examples shall
use that same version or label an intentional range.

`DEL-REQ-033`: When a deprecation period ends, the release owner shall remove a
deprecated API only after replacement tests, migration text, and the approved
removal gate pass.

### Migration, upgrade, downgrade, and rollback

`DEL-REQ-034`: Where the release supports a V2-to-V3 import, the migration
evidence shall use a V2 reader, a defined conversion, a V3 write, and a test
that does not share one storage key between V2 and V3 writers.

`DEL-REQ-035`: Where a stored format changes within V3, the format owner shall
provide mixed-version read, new-write, failure, retry, and rollback evidence
before the new writer becomes the default.

`DEL-REQ-036`: Where the release supports downgrade, the release owner shall
record a test that restores the pre-upgrade code and data from the stated
rollback point.

`DEL-REQ-037`: Where downgrade is not supported, the migration guide shall
state the irreversible boundary before the user changes code or stored data.

`DEL-REQ-038`: Where live Agent, state, Plugin runtime, or Topology upgrade is
in release scope, its owner seam shall provide an executable test for the
complete claimed transition and its failure recovery.

`DEL-REQ-039`: If an Action or Flow completes external I/O before a failed
commit, then release documentation shall state that Jido cannot roll back that
external work.

### Alignment and later implementation plans

`DEL-REQ-040`: While this seam is pending approval, the delivery alignment
shall contain only current evidence, gaps, dispositions, high-level sequence,
and acceptance gates.

`DEL-REQ-041`: When the user approves the delivery intent and requirements, the
delivery owner shall use `ce-plan` to create each detailed implementation plan
outside this seam.

`DEL-REQ-042`: When a later implementation plan is created, that plan shall map
each task to approved requirement IDs, owned files, verification, and a release
gate.

## Public contract

The delivery seam has no runtime API. Its public artifacts are the four records
in the model. Each record must be reviewable as text or structured data and
must use stable requirement and gate identifiers. A command result proves only
the exact commit, worktree, runtime, dependency set, and command that the
evidence record names.

## Invariants

- `DEL-INV-001`: Pending design text is not release proof.
- `DEL-INV-002`: A historical pass is not a current candidate pass.
- `DEL-INV-003`: A skipped assertion does not prove its target behavior.
- `DEL-INV-004`: A package compatibility claim names one exact package set.
- `DEL-INV-005`: A release-required breaking change has migration and rollback
  or an explicit irreversible boundary.
- `DEL-INV-006`: Alignment defines gates; a later implementation plan defines
  tasks.

## Downstream guarantees

| Consumer | Guaranteed contract |
| --- | --- |
| Release execution | One selected scope, package matrix, compatibility register, and evidence record. |
| Package users | Version, migration, support, and deprecation claims match the released artifact. |
| Ecosystem packages | A compatibility claim applies only to the named tested versions and sources. |
| Later `ce-plan` work | Approved requirement IDs and gates are stable planning inputs. |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `DEL-DEC-001` | How is release scope selected? | Use a requirement-level `required`, `deferred`, or `excluded` ledger. | Pending seam designs do not become release scope by inference. |
| `DEL-DEC-002` | Which package set must pass? | Require Jido, `jido_action`, and `jido_signal`; add AI or Browser only when the release claim names them. | Core can release without an unsupported ecosystem claim. |
| `DEL-DEC-003` | Who can accept a gate exception? | Name one gate-exception owner who is not the command result itself. | Exceptions have explicit human authority and expiry. |
| `DEL-DEC-004` | Which skips can remain? | Permit only requirements that the approved scope ledger defers or excludes. | No release-required behavior is hidden by a skip. |
| `DEL-DEC-005` | What is the default compatibility policy? | Keep supported V3 APIs until an owner approves a version-bounded deprecation and its removal gate. | Additive migration remains the default. |
| `DEL-DEC-006` | Are live upgrade features a V3 release gate? | Defer live Agent and Topology upgrade unless the release scope adds them. | Current skipped upgrade probes do not block the core candidate. |
| `DEL-DEC-007` | What rollback claim applies to stored data? | Require rollback proof for each supported path; otherwise state the irreversible boundary. | Documentation cannot imply an unproved downgrade. |
| `DEL-DEC-008` | How fresh must evidence be? | Run final gates on the exact candidate commit and package revisions with a clean or fully recorded worktree. | Old reports remain historical context only. |
