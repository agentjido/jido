# OTP, Agent runtime, and Topology ownership

Topology is optional. It turns a declared Agent system into supervised
components and validated connections. OTP controls process lifetimes. Jido
controls Agent state recovery. Topology reports whether the declared system
is present, connected, and ready.

## Owners

| Owner | Contract |
| --- | --- |
| OTP | Start, stop, and restart local children. Apply restart limits and shutdown order. |
| Agent runtime | Keep identity and registration stable. Restore committed state. Rebuild Agent-owned Plugin runtimes. |
| Topology | Expand groups, validate the graph, install declared components, apply accepted targets, and check connections and readiness. |
| Connection owner | Reconnect its Bus subscriptions or external connections. |
| Application | Select membership, nodes, capacity, and rebalance policy. |

Supervision, logical ownership, and readiness dependencies are separate
relationships. A logical parent and its workers can be siblings under OTP.
A Bus outage can make a worker unready while its process remains alive.
Activation order does not define restart coupling.

## Local instance

```text
Application supervisor (:rest_for_one)
├── named Jido infrastructure
└── Topology Controller instance (:one_for_one)
    ├── resource supervisor
    ├── Agent supervisor (:one_for_one)
    ├── task supervisor
    └── coordinator
```

The coordinator can restart without stopping healthy members or Buses. Its
replacement cancels prior activation tasks before it starts another bounded
pass. The
Agent supervisor retains child specifications and restarts abnormal exits.
Each start rebuilds the declared definition and runtime inputs, then restores
committed state through the AgentServer restore contract. Registration uses
the Jido instance and stable Agent ID, independent of the owning supervisor.

The Agent supervisor uses `max_restarts` and `max_seconds` from Controller
options (defaults: 3 restarts in 5 seconds). A supporting supervisor failure
stops the whole instance. The Controller child is transient: restart-limit
shutdown stays stopped. Reconciliation cannot recreate that subtree. An
application can select a different outer policy, but then owns its retry limit.

Plugin runtime wrappers remain under Jido shared infrastructure. Each wrapper
links to its Agent, owns its runtime subtree, and stops that subtree when the
Agent exits. This ownership rule also applies to Agents under an application
supervisor. Topology does not scan or stop the shared local Agent pool.
The ownership settlement event waits for the local subtrees to stop. Its
component counts now describe the watcher's remote cleanup only.

## Exit and recovery rules

| Event | Local behavior |
| --- | --- |
| Abnormal Agent exit | OTP restarts the transient child, even with manual repair or a paused coordinator. |
| Normal exit or explicit stop | The child stays stopped. Reconciliation reports it as stopped and does not restart it. |
| Hibernation | Durable state is saved; the transient child stays stopped. |
| Synchronous start failure | No child was installed. A bounded activation pass reports the error; another pass can retry installation. |
| Asynchronous bootstrap failure | The installed child exits with shutdown and stays stopped. Repair does not repeat failed bootstrap. |
| Restart limit reached | The instance shuts down. Application policy must decide whether to start a new instance. |
| Target removal | Stop the instance and start the replacement target. Additive update still rejects removals. |
| Manual repair | Initial installation runs once. Later installation and relationship repair require `reconcile/2`. OTP restart and connection recovery continue. |

A durable accepted target is retained when its instance stops. A replacement
that removes members must use a new Topology ID when that saved target is
incompatible. This is a new system identity; state migration is application
policy. Live removal and arbitrary target replacement are not supported.

For a directly supervised Agent, `Supervisor.restart_child/2` can resume its
stopped child specification. Replace a Topology instance to resume its stopped
members. A clean stop clears the local runtime checkpoint. Durable
persistence remains available. A runtime checkpoint retains committed state
only while its Jido instance remains alive; it does not survive instance or
node loss. Uncommitted work is not restored, and external effects are not undone.

Topology uses the current declared definition with restored state. Runtime
configuration and Plugin inputs are rebuilt on every start. The default
AgentServer restore mode retains the saved Agent definition, including an
accepted definition upgrade. Use `restore_definition: :current` when the
supervisor's current definition must supply configuration; the restored ID
and module must match, and the restored state must pass that definition's schema.

`on_parent_exit: :stop` causes a clean child shutdown. A transient child then
stays stopped. Use `:continue` or `:emit_orphan` when a logical child must remain
alive while its parent recovers. Reconciliation can bind live replacements;
it does not turn logical ownership into an OTP restart strategy.

## Remote and shared components

Exact-node placement remains separate from local OTP restart. Remote Agents
remain temporary children of the remote Jido pool and use the existing
placement and pending-move recovery contract. A watcher tracks remote PIDs
for cleanup when the local instance stops. Cleanup can fail across a network
partition; this does not provide a cluster ownership lease or node selection.
A replacement instance waits for the previous cleanup owner to finish before
it can reuse the same Topology ID. Startup returns `:ownership_cleanup_pending`
if that cleanup has not finished within five seconds.
Moving a local member first removes its OTP child specification so that a
concurrent restart cannot leave an old owner behind.

A declared Bus is exclusively owned by the instance resource supervisor.
A conflicting shared Bus or Agent identity is rejected and left untouched.
Bus clients own reconnection. Topology checks their current readiness without
restarting the Agent during a Bus outage.

Use ordinary application supervision for a fixed set of Agents. Add Topology
when group expansion, graph validation, declared connections, aggregate
readiness, or accepted target and placement changes are required.
