# Agent Server Lifecycle

`Jido.AgentServer` is the OTP owner of one live Agent. It uses `:gen_statem` to
keep runtime phases explicit while work runs in supervised tasks.

## Activation

Startup constructs or accepts one Agent instance, applies restore policy, starts
Plugin runtimes, and waits for their readiness checks. `start_link/1` keeps the
standard OTP start contract and can return during initialization. Use
`await_ready/2` for a directly started Server. `Jido.start_agent/3` waits for
Plugin readiness and any required initial persistence write.

Instance lookup does not return the Server during this provisional period. A
Registry entry reserves the identity, but public lookup and listing accept only
the `:ready` value.

Each activation has a new activation ID. A restarted Server can keep the same
Agent ID and state version.

## Runtime Phases

The public status can report initialization, idle work, admission, executable
work, and Directive dispatch. The Server handles one Agent Turn at a time.
It keeps its mailbox responsive while Plugin admission, Jido Action execution,
Plugin dispatch, and child lifecycle operations run in owned tasks. Explicit
child adoption and stop calls wait for idle, then use the directing phase.
They do not change the Agent state or commit revision.

The Server applies `turn_timeout` from active admission until commit starts.
It cancels owned pre-commit work on timeout. Directive work starts after commit
and uses `directive_timeout` for Plugin callbacks, external Signal dispatch,
and remote child placement. Local supervisor starts remain tracked until the
supervisor replies. Killing the caller cannot cancel that start. A Server stop
closes its owned child requests so a late start cannot leave an owned child.

Each Turn starts an owned local execution under the instance Runic Runner.
Runic stops its Worker and native task scope when the Server exits, including
abrupt Server death. Core confirms cleanup before commit or the next Turn.
Without persistence, execution stays in memory and interrupted Flows do not resume.
With persistence, AgentServer saves Flow progress at step boundaries and restores
the current Turn after a crash.

Do not read private state-machine tuples. Use:

```elixir
agent = Jido.AgentServer.agent(server)
status = Jido.AgentServer.status(server)
snapshot = Jido.AgentServer.snapshot(server)
children = Jido.AgentServer.children(server)
```

## Attach Owners

`attach/2` monitors an owner process and prevents idle shutdown. Repeated
attachment of the same owner is safe. `detach/2` removes it. Owner death also
removes the attachment. When the last attachment is gone, the idle timer can
start.

`touch/1` resets the idle timer without attaching an owner.

## Restart And Stop

The Jido instance stores an ephemeral runtime checkpoint after each commit. An
abnormal Agent Server restart can recover that value while the owning Jido
instance stays alive. A normal stop removes the runtime checkpoint.

Configured persistence is separate. It can restore state after the complete
instance or VM restarts. A new persistent Server confirms a revision-zero
record after Plugin readiness and before its start call succeeds.

A persistent activation restores after its Server or supervisor fails. A new
explicit `:create` start still rejects an existing record. Persistent members
of an Agent's inline topology retain their slot IDs and restore their own last
confirmed records. Removing a slot ends that identity. Adding it again creates
a new identity. These records do not form an atomic family snapshot.

Start an AgentServer with a persistence adapter to run routed
Flows as durable serial Turns. The Server saves acceptance before dispatch,
confirms graph checkpoints before further work, and commits the final Agent state
and completion receipt together. Other state-changing Turns wait. Reads, status,
and cancellation stay available. No durability Plugin or completion route is needed.

```elixir
{:ok, server} = Jido.start_agent(MyJido, ReportAgent,
  id: "report-agent", persistence: :inherit)
:ok = Jido.AgentServer.await_ready(server)
Jido.AgentServer.call(server, report_signal)
Jido.AgentServer.status(server).durable_turn
# %{id: turn_id, status: :completed}
```

The application supplies retained storage and starts known roots after BEAM loss.
The OTP supervisor restarts processes within a live BEAM. AgentServer restores
saved work; Runic restores graph progress. Interrupted Actions start again from
their beginning. The registration guard stops a Server whose activation has died
before it admits a replacement with the same identity. A member restart keeps
the root and its other members active. Caller handles, queued Signals, post-commit hooks, and effects
are not durable. Repeated Signals start new Turns.

Implementation and test order:

1. Save the accepted Turn with its Agent; reject nonportable context before dispatch.
2. Confirm each graph checkpoint; a rejected save must block the next Action.
3. Restore the same Turn after Worker, Server, or activation loss; steps 1–5 must
   not repeat when step 6 was interrupted.
4. Save cancellation before stopping work; commit completion with the candidate
   Agent. Test a crash after the write but before its reply.
5. Restore topology member identities and independent records. Kill a writer BEAM
   and restore the same pending Turn in a fresh BEAM.

See [Core Turn tests](../test/jido/agent_server/durable_turn_test.exs),
[topology tests](../test/jido/agent_server/durable_topology_test.exs), and
[the examples](../examples/11_durable/README.md).

Use `Jido.stop_agent/3` when the instance owns the Server. Use
`Jido.AgentServer.stop/3` for a direct Server reference. A `Stop` Directive
stops the Server after its current state commit.

## Idle Hibernation

An idle Server with persistence can save and stop through `hibernate/2`. A later
`Jido.thaw/4` loads the checkpoint and starts the Agent again. Hibernation is not
available during active Turn work. An active record does not mean that a Server
is live. Normal durable delete uses a tombstone, not a hibernated record kind.

## Explicit Upgrade Boundary

Use `Jido.AgentServer.upgrade/2` to run a zero-arity installation operation
after the Server becomes idle. An upgrade request waits behind active Turn and
Directive work. Signals that arrive after the request remain behind it in the
Server event order. This operation coordinates installation; it does not pin
arbitrary BEAM module loads.

Use `Jido.AgentServer.upgrade/3` to migrate the committed Agent to a target
module. The migration receives the current Agent and returns one complete state
map. The target must keep the same Agent identity and Plugin declarations. Jido
validates and checkpoints the target before it becomes visible, then advances
the state version once. Cross-module durable migration requires a stable Jido
namespace key. This operation does not migrate private Server state or Plugin
runtime structure.

See [Calls, Casts, And Requests](calls-casts-and-requests.livemd),
[Runtime State And Debugging](runtime-state-and-debugging.livemd), and
[Compare And Swap, Hibernate, And Thaw](compare-and-swap-hibernate-and-thaw.md).
