# Orphans & Adoption

**After:** You can let a child survive logical parent death, inspect the orphan transition explicitly, and reattach that child to a new coordinator when the workflow truly requires it.

> This is an advanced orchestration pattern.
>
> Most Jido hierarchies should keep the default `on_parent_death: :stop`. Reach
> for orphaning only when the child owns long-running or business-critical work
> that should outlive the original coordinator. Orphan survival is about live
> runtime continuity, not automatic storage-backed durability.

## Architecture: Logical Hierarchy, Not OTP Parenthood

Jido's parent/child relationship is **logical**, not OTP supervisory ancestry.

- Parent and child agents are still OTP peers under a supervisor.
- The relationship is tracked with `Jido.AgentServer.ParentRef`, child-start signals, and process monitors.
- `on_parent_death` describes what the child should do when its **logical** parent disappears.

That distinction matters because a surviving child is not "crashing" in OTP terms. It is following a Jido lifecycle policy.

## Lifecycle States

| State | `state.parent` | `agent.state.__parent__` | `state.orphaned_from` | `agent.state.__orphaned_from__` |
|------|----------------|--------------------------|-----------------------|---------------------------------|
| Standalone agent | `nil` | `nil` | `nil` | `nil` |
| Attached child | `%ParentRef{}` | `%ParentRef{}` | `nil` | `nil` |
| Orphaned child | `nil` | `nil` | `%ParentRef{}` | `%ParentRef{}` |

Current parent routing always uses `state.parent` / `agent.state.__parent__`.

Former-parent provenance always uses `state.orphaned_from` / `agent.state.__orphaned_from__`.

## Parent Death Policies

| Option | Behavior | Typical use |
|--------|----------|-------------|
| `:stop` | Child shuts down when parent dies | Default. Most coordinators and ephemeral workers |
| `:continue` | Child survives and becomes orphaned silently | Long-running work that should finish without intervention |
| `:emit_orphan` | Child survives, becomes orphaned, then handles `jido.agent.orphaned` | Durable work that needs explicit orphan recovery logic |

When orphaning happens, Jido clears the current parent reference first, then exposes the former parent snapshot. This avoids the stale-state bug where child code could still try to talk to a dead parent.

## What Changes During Orphaning

When a child becomes orphaned:

- `state.parent` is cleared
- `agent.state.__parent__` is cleared
- `state.orphaned_from` is populated with the former `ParentRef`
- `agent.state.__orphaned_from__` is populated with the same former `ParentRef`
- `Directive.emit_to_parent/3` starts returning `nil`

If the child uses `on_parent_death: :emit_orphan`, it also receives `jido.agent.orphaned` with:

- `parent_id`
- `parent_pid`
- `tag`
- `meta`
- `reason`

The orphan signal is delivered **after** detachment, so the handler sees orphaned state, not attached state.

## Spawning a Recoverable Child

```elixir
Directive.spawn_agent(MyWorker, :worker,
  opts: %{
    id: "worker-123",
    on_parent_death: :emit_orphan
  },
  meta: %{role: "crawler"}
)
```

While attached, the child can respond normally:

```elixir
reply = Signal.new!("worker.result", %{ok: true}, source: "/worker")
Directive.emit_to_parent(%{state: context.state}, reply)
```

After orphaning, the same helper returns `nil` until the child is explicitly adopted.

## Handling `jido.agent.orphaned`

Use `:emit_orphan` when the child needs to take a concrete action after losing its coordinator.

Typical orphan handlers:

- mark the agent as orphaned in domain state
- emit a signal to an external bus, topic, or audit sink
- downgrade work from interactive to background mode
- await explicit adoption by a replacement coordinator

Example:

```elixir
defmodule HandleOrphanedAction do
  use Jido.Action,
    name: "handle_orphaned",
    schema: [
      parent_id: [type: :string, required: true],
      parent_pid: [type: :any, required: true],
      tag: [type: :any, required: true],
      meta: [type: :map, default: %{}],
      reason: [type: :any, required: true]
    ]

  def run(params, context) do
    former_parent = Map.get(context.state, :__orphaned_from__)
    can_reply = Directive.emit_to_parent(%{state: context.state}, %{type: "noop"}) != nil

    {:ok,
     %{
       orphaned: true,
       orphaned_from_id: former_parent && former_parent.id,
       orphan_reason: params.reason,
       can_reply_to_parent?: can_reply
     }}
  end
end
```

`can_reply_to_parent?` should be `false` here. If it is `true`, you are still holding stale routing state somewhere.

## Adoption Is Explicit

Use `Directive.adopt_child/3` to attach an orphaned or unattached child to the current parent:

```elixir
Directive.adopt_child("worker-123", :recovered_worker, meta: %{restored: true})
```

Adoption:

- resolves the child by PID or child id
- requires the child to be alive
- requires the child to be unattached
- rejects tag collisions in the adopting parent
- installs a fresh `ParentRef` and parent monitor
- clears orphan markers
- restores `emit_to_parent/3`

After adoption, the child is visible through `Jido.get_children/1` on the new parent and can send results back to that parent again.

## End-to-End Flow

1. A coordinator spawns a child with `on_parent_death: :emit_orphan`.
2. The child uses `emit_to_parent/3` normally while attached.
3. The coordinator dies.
4. The child survives, becomes orphaned, and receives `jido.agent.orphaned`.
5. A replacement coordinator explicitly adopts the child by id.
6. The child resumes parent-directed communication with the new coordinator.
7. If that child later restarts, it rehydrates the adopted relationship from `Jido.RuntimeStore`.

The canonical runnable example for this flow lives in `test/examples/runtime/orphan_lifecycle_test.exs`.

## When to Use Each Policy

Prefer `:stop` when:

- the child is only meaningful while the original coordinator is alive
- work can be safely restarted later
- you want OTP restart semantics to remain simple

Consider `:continue` when:

- the child should finish in-flight work
- no immediate recovery workflow is needed
- surviving silently is enough

Use `:emit_orphan` when:

- the child needs to react to losing its coordinator
- you plan to adopt the child later
- you want explicit auditability of the orphan transition

## Caveats

- Jido does not automatically reconnect children when a logical parent restarts.
- Adoption is explicit to avoid accidental dual ownership.
- Child tags are parent-local ownership keys, not global identity.
- `emit_to_parent/3` is only for currently attached children. Orphan-aware logic should read `__orphaned_from__` or the `jido.agent.orphaned` payload instead.
- The current logical relationship is mirrored into `Jido.RuntimeStore`, which is instance-local and ephemeral. Its ETS table survives `RuntimeStore` process restarts, but it still resets when the owning Jido instance stops.

## Testing and Evaluation

Treat orphaning as a real lifecycle, not an implementation detail. Good tests should verify:

- the child still works while attached
- the parent reference is cleared on orphaning
- the orphan signal sees detached state
- `emit_to_parent/3` returns `nil` while orphaned
- explicit adoption restores `Jido.get_children/1` and child-to-parent messaging
- adopted child restarts still bind to the adopted parent
- a second parent death re-triggers the orphan lifecycle

For a CI-ready acceptance test covering that full path, see `test/examples/runtime/orphan_lifecycle_test.exs`.

## Related

- [Runtime](runtime.md)
- [Multi-Agent Orchestration](orchestration.md)
- [Directives](directives.md)
- [Testing](testing.md)
