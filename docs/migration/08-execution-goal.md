# Core Jido V3 migration goal

Approved on 2026-09-05. Execute the migration in core Jido on `v3-spike`.
Preserve a clear, ordered Git history. Redesign work is deferred.

## Objective

Transfer the implemented design, fixes, and examples from prepared source
`jido_v3@bf6c9fbec569cb6438b6a1629a2768058d439d1f` into core Jido. Keep
`Jido.Agent` and `Jido.AgentServer`. Complete the commit sequence, prove the
examples in core, run burn-in, and complete local beta candidate QA.

## Fixed inputs and scope

- Core repository: `/Users/mhostetler/Source/Jido/proj_jido_core/jido`.
- Branch: `v3-spike`. Start from the M00 commit that contains this document.
  It is a descendant of core baseline `a31b74306d4498ee47732c18b993abd4c26542bd`.
- Prepared donor worktree: `/Users/mhostetler/.codex/worktrees/0d9b/jido_v3`.
- Tested source: `bf6c9fbec569cb6438b6a1629a2768058d439d1f`.
- Report and evidence: `741058d128928d05bdee109f3c6a0425eb82db89`.
- Original Actor snapshot: `ba00fcf1f76563c9a94a01c69c2f16190997fd28`.
  Preserve it and both donor checkouts.

Keep the implemented authoring forms, Builder, Codec, Plugin callbacks, PID
interfaces, child ownership, and Topology. Do not implement F01–F06, a new Ref
facade, a new Plugin pipeline, a new persistence architecture, or cluster
authority as part of this goal. Record legacy V2 code and test removals with
their replacement behavior or an explicit migration-guide entry.

The only approved skip is DIST-03:
`test/jido/agent/distributed_authority_test.exs`, test
`one logical identity has at most one live cluster owner`. Preserve its
assertion and reason. Cluster-exclusive ownership is not a supported claim.
The other distributed-authority check and all required persistence probes run.

## Execution

Follow [M01–M14](03-commit-sequence.md); M00 is this committed plan. Use the
[file inventory](file-inventory.csv), [example manifest](example-manifest.json),
and [source hashes](sources.json). Adapt the input verifier in M01 so it checks
the fixed inputs independently of the evolving core implementation.

Transfer content from the fixed donor commit. Do not merge donor history.
Use focused Conventional Commits and source trailers. Each final commit must
compile and pass the tests for the code included through that commit. Keep
existing published core history intact. Do not introduce temporary Actor APIs,
empty implementations, weaker assertions, or additional skips.

Use ASD-STE100 Simplified Technical English. Do not use skills unless the user
requests them. Apply repository instructions, including the rule against manual
CHANGELOG edits. Keep beadwork absent. No push, force-push, PR merge, package
publication, or sibling-package rewrite is part of this goal.

## Completion checks

1. All 52 catalog fixtures, shared support, supporting core tests, and all 10
   application scenarios run and pass in core. Source differences have a reason
   and a test. Every old core file and test has a recorded disposition.
2. The full core suite passes with only the exact DIST-03 skip. The gate rejects
   missing or empty selections and all unexpected skips or failures.
3. The seeds 0–9 campaign and the 30-minute workload in
   [validation](05-validation.md) pass with recorded recovery and cleanup results.
4. Core passes coverage, meaningful lint checks, compilation, Dialyzer, docs,
   packaging, runtime support checks, and a fresh package-consumer test. Check
   representative downstream contracts and the applicable main-branch fixes.
5. The migration guide, validation evidence, and final commit series are ready
   for review. The goal report states the tested core SHA, source SHA, commits,
   results, skip, and remaining support limits. The core worktree is clean.

Create an active goal in the execution task with this objective. No token budget
was requested. Do not mark it complete from donor results alone. If a required
check is blocked, record the exact cause and continue independent work.
