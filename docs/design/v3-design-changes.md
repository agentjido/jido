> Deferred design proposal. This document is pending approval. It does not define
> the current core API. See [the implemented contract](../migration/01-contracts.md).

# v3 design changes

[Design overview](README.md)

This document compares current spike concepts with the proposed v3 design. It
is not a normative v3 API specification.

## Agent and authoring

| Current concern | Proposed v3 direction |
| --- | --- |
| Separate definition or instantiation language | Every Agent comes from one versioned Agent module and is a complete immutable value. |
| Ambiguous state setters or patches | Use complete `replace_state/2` and `replace_plugin_state/3` values. |
| Persistence callbacks on Agent modules | Use fixed core checkpoint and restore functions. |
| Restore against changed module code | Require the exact saved module and definition revision. |
| Runtime Builder and core authoring Codec | Remove them from core. A future authoring package must resolve output to a versioned Agent module. |
| Agent `to_map/1` and `from_map/1` | Remove them. Checkpoint is instance-state persistence, not authoring serialization. |
| Overridable `handle_signal/2` routing | Resolve declared routes directly before Plugin preparation. |
| Multiple matching routes fail | Select the first Signal Router match. |

Agent state, Plugin state, Plugin prepared input, and Directives now use one
recursive portable-term rule in addition to their Zoi schemas.

## Plugin contracts

| Current contract | Proposed v3 contract |
| --- | --- |
| `prepare/2` and `admit/3` | Pure `prepare/2` in the fixed evaluator. |
| Shared command context | One isolated prepared input for each Plugin ID. |
| Complete state before and after contribution input | One declared `%Jido.Plugin.Transition{}` projection. |
| `state_spec/1` | Static `state_schema` declaration. |
| `update_state/3` | Pure `contribute/2`. |
| `directives/1` | Static owned Directive declaration. |
| `validate_directive/2` | Zoi schema and portable-term validation on each Directive. |
| `prepare_dispatch/4` | Removed. Send a Signal or dispatch an owned Directive. |
| Runtime restart from original input | Replacement from a fresh Init with latest committed Plugin state and version. |

The executable output stays private to the evaluator. A Plugin sees only its
owned prepared input, declared Agent fields, and owned Turn Directives. There
is no public `Jido.Agent.Turn.Result`.

## Live runtime API

The proposed v3 design keeps an internal `:gen_statem` Agent Server.
Applications and packages do not call it. The generated Ref-first Jido instance
facade is the only public live command, lifecycle, cancellation, and inspection
boundary.

`cast/3` is a best-effort send. Its `:ok` result does not confirm admission,
evaluation, or commit. Only evaluation is cancellable. `turn_timeout` is
independent from caller wait time. Commit and Directive work are not
cancellable.

The error policy is closed data: `:continue` or `:stop` after a normal
pre-commit error. The proposed v3 design removes function-valued error policy
hooks.

An abnormal persistent restart loads the latest Record. An abnormal
nonpersistent restart resets to the exact initial Agent and state version zero.

## Persistence and effects

| Current concern | Proposed v3 direction |
| --- | --- |
| Instance module also acts as durable identity | A stable namespace is part of `Jido.Agent.Ref`. |
| PID or Agent ID runtime calls | Public live operations use the complete Agent Ref. |
| Per-Agent persistence adapter | One Jido instance persistence provider is authoritative. |
| Blind byte `put` and `delete` | Compare-and-swap Records and tombstone deletion. |
| Recovery implicit in all Directives | Explicit capability stores portable work intent and IDs in Agent or Plugin state. |
| New Turn can replace pending work | Plugin state preserves pending work; completion is a later Signal and commit. |
| Persistence error can leave a Server active | Every write error removes write authority and stops the current Server. |

Persistent creation waits for provisional Plugin runtime readiness before it
writes the initial active Record. A readiness failure writes no Record.

The Agent Server checks `new_state_version == old_state_version + 1`. Commit
does not store a duplicate prior state version. Record `storage_version` is the
compare-and-swap guard.

## Runtime topology

| Current runtime | Proposed v3 runtime |
| --- | --- |
| Mixed `AgentSupervisor` children | `AgentPool` contains Agent Servers only. |
| Plugin wrappers in Agent supervisor | Owner-bound hosts live in `PluginRuntimePool`. |
| Parent and child PID policy in core | Remove logical relationship policy from core. Use Agent or Plugin state or a package. |
| Generic `Spawn` child specifications | Remove them from the core Agent Directive set. |
| `:one_for_one` Jido root | Use dependency-ordered `:rest_for_one`. |

Agent Refs and Signal delivery remain in core. Parent tags, adoption,
cascading termination, and relationship views do not.

## Results, errors, and observation

`Result` now means only the tagged live reply at the commit boundary. Direct
`Agent.cmd/3` returns an evaluation value with a candidate Agent and Directives.

Command, construction, and lifecycle failures use defined composed Splode
errors. Map-style fetch and OTP asynchronous response values remain explicit
protocol exceptions.

Core telemetry publishes semantic lifecycle, Turn, Commit, persistence,
Directive, admission, and settlement boundaries. It does not publish stable
events for internal evaluator stages and does not keep a debug timeline in
Agent Server state.
