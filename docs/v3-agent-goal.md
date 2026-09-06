# Proposed goal: Jido V3 with Agent names

Status: proposed; implementation has not started.

Planning snapshot: 2026-09-05. The source work is now committed in `jido_v3`
at `ba00fcf1f76563c9a94a01c69c2f16190997fd28`. Core implementation remains at
`10ebacd4`. Tests were not rerun for these snapshots.

Rebuild core Jido V3 from `10ebacd4`, using a fixed snapshot of the current
`jido_v3` source and examples. Keep `Jido.Agent` as the public model. Use
`Jido.AgentServer`, `Jido.Agent.Directive`, and established agent function names.
Permit new internals and documented V3 contract changes. Prove the design with
the example library. Finish with a small, tested commit series ready for review.
Keep the separate `jido_v3` repository unchanged.

## Method

1. **Save the source.** Copy tracked files and required untracked source, tests,
   and documents into a separate snapshot. Preserve deletions. Record the source
   commit, file hashes, and dependency lockfile. Exclude credentials, build files,
   and downloaded dependencies. A clone of HEAD alone will miss current work.
   Use this snapshot for the whole goal; add later experiments through a separate
   task.

2. **Fix the public contract.** Write one short map for modules, startup APIs,
   DSL terms, action context, result fields, telemetry, and checkpoint formats.
   Preserve established names where possible. List intentional changes to
   commands, plugins, state, and persistence. Test the retained interfaces.
   Check callers in `jido_ai` and `jido_browser` to identify migration needs;
   keep changes to those packages outside this goal. Keeping the Agent name
   does not establish V2 behavior compatibility.

3. **Build in a core worktree.** Start at `10ebacd4`. Transfer the selected final
   implementation under Agent names, with one minimal example that compares
   direct execution and live execution. Add the remaining runtime, persistence,
   plugin, authoring, and topology features with their examples in complete
   commits. Remove replaced V2 code. Copy source content without merging or
   replaying the experimental Git history. Each final commit must compile and
   pass its applicable tests. Update repository instructions to match the new
   contract.

4. **Run the examples against core.** Port all 52 current catalog fixtures and
   their acceptance tests into core. Keep stable example IDs and record path
   changes. Cover Basic, Workflow, LLM, Runtime, Multi-agent, Factory, and
   Topology. Preserve behavior assertions. Add one manifest and one command
   that runs every accepted example and its supporting core tests. Normal
   `mix test` and the current `mix examples` alias do not cover this set.
   List the 8 research folders separately with explicit capability limits.

5. **Burn in and finish.** Reproduce the saved survey findings on the snapshot.
   Add regression tests for confirmed defects in accepted features, including
   remote deadlines, remote liveness, hibernate/thaw, and group recovery.
   Run the full accepted suite with 10 recorded seeds. Run a 30-minute workload
   with concurrent commands, worker crashes, restore, and cleanup checks.
   Include real Erlang nodes for remote features. Use deterministic provider
   adapters for required LLM and Factory tests. Keep paid live-provider runs
   optional, with an explicit budget. Run quality, coverage, docs, and CI on
   the declared supported runtimes. Fold repair commits into their owning
   commits before publication, then verify the final series again.

## Done

- Core exposes Agent names; executable examples use them.
- All 52 catalog fixtures have explicit passing acceptance checks.
- Required checks have no unexplained failures or hidden skips.
- Research limits, intentional breaks, and package migration needs are recorded.
- Repeated runs prove state, commit, recovery, and resource cleanup assertions.
- CI runs the acceptance command explicitly.
- History contains complete changes; the source snapshot and donor remain safe.

## Inspection notes

- Before this planning commit, local and GitHub `v3-spike` both ended at
  `10ebacd4`. This commit adds planning documentation only.
- The prior local tip is saved as `backup/v3-spike-before-agent-reset-20260904`.
- At the initial inspection, the donor was at `bd05a32` with 116 modified,
  120 deleted, and 169 untracked files. The source snapshot above records that work.
- The saved SDK survey reports 878 of 881 tests passing and additional diagnostic
  failures. These are prior results, not a fresh validation of the current files.
- Evidence: `jido_v3/docs/reviews/2026-09-04-sdk-survey/README.md`,
  `jido_v3/examples/README.md`, and `jido_v3/test/test_helper.exs`.
