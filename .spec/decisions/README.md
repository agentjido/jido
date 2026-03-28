# `.spec/decisions`

Use this folder for durable cross-cutting decisions that shape the current Spec Led Development workspace.

<!-- covers: spec.workspace.decisions_readme_present -->

## What Belongs Here

- ADRs that affect multiple authored subjects
- verification policy that should stay consistent over time
- package-wide or workspace-wide operating rules that are more stable than a pull request discussion

## What Does Not Belong Here

- in-flight proposal notes
- branch-local implementation plans
- one-off rationale that only matters inside a single subject file

## Workflow

1. Update the current-truth subject specs in `.spec/specs/`.
2. Add or revise an ADR here only when the change is cross-cutting and should stay durable.
3. Use Git history and pull requests as the time dimension for how the change evolved.
