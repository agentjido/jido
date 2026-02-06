# Refine Identity

Goal: reduce developer friction by shrinking the core identity surface area, clarifying behavior, and isolating optional capability semantics.

## Step 1: Standardize Extension Keys

Friction addressed:
- Extension namespace uses atoms in helpers but tests use strings, leading to split namespaces.

Proposal:
- Pick a single key type for extensions and enforce it everywhere.
- Recommend atoms for plugin namespaces (consistent with `state_key`).

Implementation notes:
- Update `Jido.Identity.Agent` extension helpers to guard for atoms and raise an `ArgumentError` with a clear message when non-atoms are supplied.
- Update tests to use atom keys (`:character`, `:safety`, `:internal`).
- Document the requirement in `Jido.Identity` moduledoc and the helper docs.

Outcome:
- Extension storage becomes predictable and avoids silent duplication.

## Step 2: Make Identity Initialization Consistent

Friction addressed:
- `Identity.Agent` helpers create identity implicitly, but `Identity.Actions.Evolve` errors when identity is missing.

Proposal:
- Decide on one of these behaviors and apply everywhere:
- Preferred: implicit creation via `Identity.new/1` when missing.
- Alternative: require explicit `Identity.Agent.ensure/2` and have helpers return `{:error, :missing_identity}` (breaking change).

Implementation notes:
- If implicit creation is chosen, update `Identity.Actions.Evolve` to call `Identity.Agent.ensure/2` or inline `Identity.new/1` when missing.
- Update docs for `Identity.Agent.ensure/2` to clarify this is the canonical initializer.

Outcome:
- Developers no longer need to memorize which calls require manual setup.

## Step 3: Trim Core Identity to the Minimum

Friction addressed:
- Core struct encodes capabilities (`actions`, `tags`, `io`, `limits`) and public extension filtering, which many users will not need.

Proposal:
- Keep `Jido.Identity` minimal with `profile`, `extensions`, `rev`, timestamps.
- Move capability semantics to an optional module or plugin (e.g. `Jido.Identity.Capabilities`).

Implementation notes:
- Remove `capabilities` from `Jido.Identity` defaults and schema.
- Move `actions/2`, `tags/2`, `limits/2`, `io/2` helpers into a new module that works off extension data or its own dedicated state key.
- Provide a small migration path: a shim module or deprecation warnings in existing helpers.

Outcome:
- Core identity is a stable primitive; power users opt into richer semantics.

## Step 4: Tighten Plugin Responsibilities

Friction addressed:
- Default plugin is present but inert and partially implements checkpointing.

Proposal:
- Make the default plugin purely declarative (reserves key, singleton) until persistence is a real feature.
- If checkpoint/restore is desired, implement it fully with actual stored identity data.

Implementation notes:
- Remove `on_checkpoint/2` and `on_restore/2` from the default plugin or implement a full round-trip.
- Clarify in docs that the default plugin does not initialize identity.

Outcome:
- Less surprise and less implied behavior.

## Step 5: Make Mutation Behavior Deterministic

Friction addressed:
- `mutate/2` bumps `updated_at` with wall clock time, reducing determinism.

Proposal:
- Allow passing `now` explicitly for deterministic updates, or move timestamp management to callers.

Implementation notes:
- Add `mutate/3` with optional `now` parameter and update internal calls to accept an optional `now` in opts.
- Keep `mutate/2` defaulting to wall clock to preserve current behavior.

Outcome:
- Easier testing and replay without sacrificing default convenience.

## Step 6: Reduce Surface Area in `Identity.Agent`

Friction addressed:
- Helper API is large and overlaps with capability semantics.

Proposal:
- Keep only essential helpers in core `Identity.Agent` and move the rest into `Identity.Capabilities` and `Identity.Extensions` modules.

Minimal core helper set:
- `key/0`
- `get/2`
- `put/2`
- `update/2`
- `ensure/2`
- `snapshot/1` (optional, if it remains after Step 3)

Implementation notes:
- Deprecate capability helpers and extension helpers in `Identity.Agent` with guidance to new modules.
- Provide migration docs and examples.

Outcome:
- A smaller, more teachable core API and less developer overwhelm.
