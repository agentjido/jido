# Runtime Coordination State

Jido uses different kinds of state. Choose the kind from its necessary lifetime
and owner.

| State kind | Owner | Lifetime | Portable |
| --- | --- | --- | --- |
| Complete Agent state | Agent value | Until the next value replaces it | Yes |
| Plugin-owned Agent field | Declaring Plugin | Same as complete Agent state | Yes |
| Plugin runtime state | Runtime process | Process lifetime | Not necessary |
| Runtime coordination state | Jido instance | Instance lifetime | Not necessary |
| Persistence checkpoint | Persistence adapter | Adapter-defined | Yes |

## Complete Agent state

The Agent has one complete `agent.state` map. Use domain fields for facts that
define what the Agent knows now. Use one Plugin-owned top-level field for
portable facts that one Plugin owns. These fields commit together through the
Turn boundary and enter the same checkpoint. There is no separate Plugin state
map.

## Plugin runtime state

Use a Plugin runtime for resources that need a process lifecycle. Examples are
a connection, poller, watcher, or worker pool. Runtime state can contain local
process resources because it does not enter the Agent checkpoint. Store only
the portable configuration necessary to rebuild it in the complete Agent state.

## Instance coordination state

The internal runtime store holds data that several runtime components in one
Jido instance must share. It uses named hives to keep concerns separate. Jido
uses it for facts such as parent-child bindings and ephemeral restart
checkpoints.

The ETS table is owned by the Jido instance supervisor. It can survive a store
process restart, but it ends when the owning Jido instance ends. It is not a
database and is not a public durable-state extension point.

## Persistence state

Use `Jido.Persistence` when an Agent must survive the loss of its process, Jido
instance, or BEAM node. The adapter stores binary records and applies the
durability policy of the host application.

Persistence saves Agent checkpoints. It does not save mailboxes, running tasks,
Plugin runtime processes, Signal bus subscribers, or all data in the internal
coordination store.

## A selection rule

Ask these questions in order:

1. Is this a portable fact that must commit with the Turn? Put it in a domain
   field or the owning Plugin's field in the complete Agent state.
2. Is this a process resource that you can rebuild? Put it in a Plugin runtime.
3. Is this short-lived coordination for one Jido instance? Let the owning Jido
   subsystem use runtime coordination state.
4. Must it survive the instance or node? Put a portable fact in Agent state and
   configure persistence.

This separation keeps durable data small and makes restarts predictable.
