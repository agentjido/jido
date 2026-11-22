---
title: Bundle the Ecto Agent state Plugin
type: implementation-plan
date: 2026-11-21
last_reviewed: 2026-11-22
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Bundle the Ecto Agent state Plugin

## Goal Capsule

- Use `state do ecto CounterState end` to select the built-in Plugin.
- Use the existing admission, reduction, and commit callbacks.
- Make and verify the change in the local spike.

## Product Contract

### Summary

An Agent can use an application Ecto schema as its state source. Each live
Turn loads the current row by Agent ID.

### Problem Frame

The test-only Plugin uses a hard-coded Counter schema, and a write after
commit can fail after the caller receives success.

### Actors

The Agent, the application Repo and schema, and other writers of the row.

### Requirements

- R1. Accept one `ecto SchemaModule` declaration with no options. Reject
  explicit `schema` or `initial_state` in the same state block.
- R2. Read the row at admission. Let a pure Action propose fields to change.
  Save through the application changeset before Jido acknowledges the Turn.
- R3. Fail a stale write. Keep the newer row and skip post-commit effects.
  A fresh Turn reads the new row.

### Key Flows

Admission gives the Action the loaded row as Plugin runtime input. An
`EctoState.update/1` Directive carries proposed fields. The Plugin reduces
the Directive to one proposal. Before commit, the Plugin uses the admitted
row and the schema changeset for an optimistic update.

### Acceptance Examples

- The Counter reads 10 and saves 12 before its committed reply.
- A row changes from 10 to 40 during a Turn. The Turn fails with
  `:stale_ecto_state` and writes no ledger entry. A fresh Turn saves 42.
- A missing row or invalid changeset fails the Turn.
- A Turn without a proposal can read the row without advancing its version.
- Both orders of the Ecto and Joi declarations fail at compile time.

### Success Criteria

Compile authoring fixtures. Run live SQLite Turns and inspect their
acknowledgments, rows, and ledger entries.

### Scope Boundaries

One existing row per Agent, one primary key, and one integer
`lock_version` column. Disable Jido persistence for Ecto writes.

### Key Decisions

Apply [ADR 0019](../adr/0019-one-owner-for-agent-state-fields.md).
The application schema exports `repo/0` and `changeset/2`. The application
creates the row and advances its version on every write.

### Rejected Alternatives

An `after_commit/3` write cannot make a rejected database update fail the
Turn. The ledger can use that notification.

### Dependencies

Use the existing optional `ecto_sql` dependency and the existing SQLite
test fixture.

### Outstanding Questions

Joint atomicity with a durable Jido receipt is a separate design decision.

### Sources

[Ownership decision](../adr/0019-one-owner-for-agent-state-fields.md) ·
[Admission input](../../lib/jido/plugin/context/admission.ex) ·
[Commit hook](../../lib/jido/plugin.ex)

## Planning Contract

### Product Contract Preservation

R1 expands authoring to a built-in Plugin. R2 and R3 keep the established
state ownership and acknowledgment rules.

### Current System

The spike defines its Plugin inside the Counter test. It carries a database
version in reply data and hard-codes the Repo update.

### Target System

The Agent DSL lowers the Ecto declaration to ordinary Plugin configuration.
The Plugin receives the exact admission snapshot at pre-commit. The reply
can have any shape that the route declares.

### Key Technical Decisions

- KTD1. Lower the single-module declaration into the existing Plugin
  provider machinery. Enforce schema exclusivity in Agent authoring.
- KTD2. Use an owned Directive for the proposal. Reuse the Plugin's transient
  runtime input for the optimistic update. Keep Ecto calls in the capability.
- KTD3. Use the application's changeset and Ecto optimistic lock. Require an
  actual write for every proposal, including an unchanged value.

### System Boundaries and Change Surface

The Agent DSL owns declaration checks. The Ecto capability owns database
access and changeset validation. AgentServer passes the same Plugin's
runtime input to its pre-commit callback. The application owns the Repo,
migration, data, and optional ledger.

### Implementation Units

- U1. Add the declaration and enforce exclusivity (R1, KTD1). Compile a
  valid Agent and reject duplicate declarations and options.
- U2. Add the built-in capability and move the SQLite example to it (R2, R3,
  KTD2, KTD3). Exercise normal writes, stale writes, and read-only Turns.
- U3. Update the authoring guide, ADR, architecture map, and Covenant
  contracts. Run the final checks for U1 and U2.

### Work Graph

U1 and U2 meet at the public definition. U3 verifies the integrated result.

### Verification Contract

Run from the spike worktree.

| Gate | Requirements | Done signal |
| --- | --- | --- |
| `mix test test/jido/agent_server/ecto_state_test.exs test/jido/agent/dsl_authoring_contract_test.exs` | R1–R3 | Compile guards and live database cases pass |
| `mix test.ci` | R1–R3 | Repository suites pass |
| `mix reach.check --arch --smells` | KTD1, KTD2 | Layer rules pass |
| `mix format --check-formatted` | U1–U3 | Formatting passes |

### Rollout and Recovery

This is a local, additive change. Applications supply their own existing row
and migration. The test Repo uses a temporary SQLite database.

### Risks and Assumptions

All writers must advance `lock_version`. A lost database response can leave
the caller uncertain about the write. The ledger is a separate effect.

### Open Planning Decisions

Joint durability with a Jido checkpoint is outside this implementation.

### Definition of Done

The declaration compiles, conflicting schemas and options fail compilation,
and live Turn results agree with their database writes. A stale write leaves
the newer row intact and produces no ledger entry.

### Planning Sources

[Agent DSL](../../lib/jido/agent/dsl.ex) ·
[Plugin pipeline](../../lib/jido/agent/plugin/pipeline.ex) ·
[SQLite Repo fixture](../../test/support/jido_persistence/ecto_support.ex)

## Adapter Results

The plan is canonical Markdown.
