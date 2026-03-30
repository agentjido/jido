# `.spec` Agent Guide

Use this folder to maintain authored Spec Led Development subjects and generated state.

<!-- covers: spec.workspace.agents_present spec.workspace.agent_prime_context -->

## First Read

1. Read `.spec/README.md`.
2. Read `.spec/decisions/README.md` and any ADRs that affect the subject you are changing.
3. Read the current `.spec/specs/*.spec.md` files before editing.

## Working Rules

- Keep one subject per file.
- Put normative statements in `spec-requirements`.
- Add `spec-scenarios` only when `given` / `when` / `then` improves clarity.
- Add `spec-meta.decisions` only when a subject depends on a durable cross-cutting ADR.
- Keep ADRs in `.spec/decisions/*.md` for cross-cutting policy only.
- Prefer targeted command verifications for behavioral proof.
- Use file-backed verifications only when the target can carry stable `covers:` markers for every covered id.
- Keep verification targets repository-root-relative.
- Use Git history and pull requests as the change log; keep `.spec` current-state only.
- At session start, run `mix spec.prime --base HEAD`.
- After code, docs, or tests change, run `mix spec.next`.
- For bug fixes, prefer `mix spec.next --bugfix`.
- If next says `needs subject updates`, update the named subject before you finish.
- If next says `ready for check`, move to `mix spec.check --base ...`.
- Use `mix spec.validate --debug` when you need low-level verifier output.
- Run `mix spec.status` when you need coverage or weak-spot summaries.
