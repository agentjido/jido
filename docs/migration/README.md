# Jido V3 migration plan

Status: core migration approved; donor preparation complete. Date: 2026-09-05.

Transfer the implemented design and examples from the prepared `jido_v3`
source into core Jido on `v3-spike`. The source now uses `Jido.Agent` and
`Jido.AgentServer`. Its required persistence, group, scheduling, and remote
lifecycle fixes are committed. The original Actor donor remains unchanged.

The complete prepared runtime, all 52 fixtures and all ten application scenarios
are now in core. M12 adds current-main protections and completes the old-feature
audit. The seed campaign, continuous workload and beta QA remain pending. See
[the execution record](10-execution-record.md) for tested checkpoints.

## Fixed inputs

| Input | Revision | Role |
| --- | --- | --- |
| Core source baseline | `a31b74306d4498ee47732c18b993abd4c26542bd` | Historical baseline with the earlier planning document |
| Core implementation base | `10ebacd4b84e79b9d5496872b94a0232c36f9c90` | SchedEx fix, before Actor introduction |
| Prepared Agent source | `bf6c9fbec569cb6438b6a1629a2768058d439d1f` | Tested source to transfer |
| Preparation report | `741058d128928d05bdee109f3c6a0425eb82db89` | Child commit containing the report and evidence |
| Original Actor donor | `ba00fcf1f76563c9a94a01c69c2f16190997fd28` | Preserved historical baseline |
| Core `origin/main` inspected | `99aa07cc90a494bf3e69332bcb6c8c0086884381` | Seven later maintenance commits to assess separately |

The prepared branch is `prep/agent-migration`. Its worktree is
`/Users/mhostetler/.codex/worktrees/0d9b/jido_v3`. The original sibling
`jido_v3` checkout remains on `main` at the Actor snapshot.

Build on the current core tip. Transfer selected content from the fixed Agent
source and record its origin. Do not merge donor Git history. `beadwork` has no
role in this work.

## Read order

1. [Prepared donor record](07-prepared-donor.md): completed commits, verified
   results, serialization policy, and remaining limits.
2. [Contracts and design decisions](01-contracts.md): public changes and the
   design proposals that remain separate.
3. [Code replacement map](02-code-map.md): additions, replacements, removals,
   retained behavior, dependencies, and downstream effects.
4. [Commit sequence](03-commit-sequence.md): ordered core work and its checks.
5. [Example transfer register](04-examples.md): all 52 catalog fixtures,
   supporting tests, 10 application scenarios, and 8 research entries.
6. [Validation and beta gate](05-validation.md): source evidence, core
   acceptance, repeated execution, and final QA.
7. [Optional design adoption](06-design-options.md): separate proposed refactors.

[File inventory](file-inventory.csv) accounts for all 278 core and 418 prepared
donor `lib` and `test` files in 632 rows. [Example manifest](example-manifest.json)
records current source paths, target paths, test mappings, and original Actor
provenance. [Source record](sources.json) fixes 667 source file hashes.

## Recommended approach

Transfer the prepared Agent implementation. Keep its fixes in the first complete
Agent/server/plugin replacement. Use later commits to add the complete example
groups and focused regression coverage. Do not recreate fixes or repeat the
Actor-to-Agent rename in core.

Each final commit must compile and pass the checks introduced through that
commit. Broader design proposals remain separate decisions. Basic, Multi-agent,
Factory, and Topology still depend on Builder, Codec, and child ownership.
The user deferred the proposed Ref facade, new Plugin pipeline, and new
persistence architecture. They are outside this migration goal. The
[execution goal](08-execution-goal.md) records the approved scope and completion checks.

The prepared source passes all 52 catalog fixtures and all 10 application
scenarios. The current full suite passes **1005 tests with zero failures and
one skip**. The user approved skipping DIST-03 on 2026-09-05. Its assertion is
retained; cluster-exclusive ownership remains unimplemented. Previous coverage
is **83.0%**. Credo ran zero checks, so lint validation remains open.

These are donor results. Core transfer is complete only after its own complete
example and regression checks pass. Then run the burn-in campaign and final
beta QA. Carry the one approved skip in the manifest. Do not claim cluster-exclusive
ownership until it is implemented and DIST-03 passes.

## Completion record

- [x] Record the original source, examples, failures, and design conflicts.
- [x] Prepare a separate donor branch with behavior fixes and Agent naming.
- [x] Verify prepared source hashes, test evidence, and retained example counts.
- [x] Update the core source manifest and proposed commit sequence.
- [x] Record the user-approved DIST-03 skip; retain its assertion and capability limit.
- [x] Approve the implemented donor design as the migration baseline; defer redesigns.
- [ ] Record each legacy API and test disposition during the transfer.
- [ ] Transfer the implementation and prove example parity in core.
- [ ] Run the 10-seed campaign and 30-minute workload in core.
- [ ] Complete final beta QA.

Repeat the plan checks with `python3 docs/migration/verify_plan.py` from core.
The [verification record](evidence/plan-checks.json) checks source hashes,
manifest selections, copied results, local links, and file inventory coverage.
It does not run Mix or change production code.

This plan is the M00 documentation checkpoint. The execution task starts from
the commit that contains it. Core production code is unchanged at this checkpoint.
