# Durability Model

By default, a committed Agent lives only as long as its activation. When you
turn persistence on, Jido stores every commit as a versioned record before the
Server replies. This guide lists what that record holds, when Jido writes it,
and what Jido never stores or replays.

```elixir
defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    namespace: "my-app/agents",
    persistence: {Jido.Persistence.Ecto, repo: MyApp.Repo}
end

{:ok, pid} = MyApp.Jido.start_agent(MyApp.Counter, id: "counter-1", persistence: :inherit)
:ok = Jido.AgentServer.await_ready(pid)                  # revision 0 is stored
{:ok, _agent, []} = Jido.AgentServer.call(pid, signal)   # revision 1 is stored first
```

When `call/3` returns `{:ok, ...}`, the adapter already holds revision 1. If
the BEAM stops now, `MyApp.Jido.thaw(MyApp.Counter, "counter-1")` starts the
Agent from that record.

## The Short Version

| Durable with an adapter | Not durable |
| --- | --- |
| The committed Agent: domain state, Plugin-owned state, definition, topology | Caller handles: `call/3` waits, `submit/3` Pending values |
| The revision of that record | Queued Signals that have not started |
| A tombstone after `delete_agent` | Caller `context:` of ordinary Turns |
| An accepted Flow Turn: its graph, open waits, and timer deadlines | Post-commit hooks and Directive effects |
| The terminal receipt of a Flow Turn | Plugin runtime processes and their memory |
| | Owners, admission state, and idle timers |

Durable data is committed data. Work in progress is durable only for routed
Flows.

## Turning It On

Persistence needs three things:

1. A Jido instance with a stable `namespace:`. The namespace is part of every
   record key.
2. An adapter, on the instance or on the start call.
3. A start option that selects it. Pass `persistence: :inherit` to use the
   instance adapter, or an adapter tuple to use another one.

`persistence:` defaults to `false` for every Agent, even when the instance has
an adapter. To make `:inherit` the default for one instance, start it with
`agent_server: [persistence: :inherit]`.

| Start option | Default | Meaning |
| --- | --- | --- |
| `persistence:` | `false` | `false`, `:inherit`, an adapter module, or `{adapter, opts}`. |
| `persistence_mode:` | `:create` | `:create` writes revision 0 and rejects an existing record. `:restore` requires one. |
| `persistence_timeout:` | `5_000` | Budget in ms for one storage operation. |

A misconfiguration surfaces when the activation starts. `start_agent/2` returns
`{:ok, pid}`, then the activation stops with a reason that `await_ready/2`
reports as an exit:

| Exit reason | Cause |
| --- | --- |
| `{:shutdown, :stable_namespace_required}` | The instance has no `namespace:`. |
| `{:shutdown, :incompatible_durable_checkpoint}` | `persistence: :inherit`, but the instance has no adapter. |
| `{:shutdown, :conflict}` | `:create` found an existing record. |
| `{:shutdown, :not_found}` | `:restore` found no record. |
| `{:shutdown, :deleted}` | `:restore` found a tombstone. |

[Make an Agent Durable](make-an-agent-durable.livemd) walks through each step.

## What A Record Holds

One record per Agent, keyed by the exact Ref `{namespace, partition, id}`:

- **State.** The complete state map: domain fields and Plugin-owned fields.
  Plugins convert their own fields with `dump/3` and `load/3`.
- **Definition and topology.** Routes, Plugins, members, and connections, as
  they were at commit. Restore does not rebuild them from the current module.
- **Revision.** A non-negative integer equal to the Server's `state_version`.
- **Flow receipt.** For a durable Flow Turn, its Turn ID, status, and portable
  context.

Every value must be portable data: maps, lists, strings, numbers, booleans,
`nil`, and atoms the codec accepts. PIDs, references, and functions are
rejected before the write. [Storage Model](persistence-storage-model.md)
describes the encoding.

Child Agents in a topology save their own records. A root record is not an
atomic snapshot of the whole family.

## When Jido Writes

| Event | Write | Revision |
| --- | --- | --- |
| A new activation with `:create` | Revision 0, before `await_ready/2` returns `:ok` | 0 |
| A successful Action Turn | The candidate, before the reply | +1 |
| A Turn that returns identical state | A new record anyway | +1 |
| A Turn that fails before commit | Nothing | unchanged |
| A Flow Turn is accepted | Acceptance, saved with the Agent, before execution | +1 |
| A Flow step completes | A graph checkpoint, before the next step starts | unchanged |
| A Flow Turn completes | The candidate and the terminal receipt in one write | +1 |
| A Flow Turn fails or is cancelled | A terminal receipt with unchanged state | +1 |
| `hibernate/2` | The current Agent at its current revision | unchanged |
| `delete_agent/3` | A tombstone | barrier kept |

Every write is a compare-and-swap against the revision the Server last read.
If the stored record moved, the write fails with `{:error, :conflict}` and
nothing is replaced. [Revisions and Conflicts](durable-revisions-and-conflicts.md)
covers the rules.

## The Fail-Stop Rule

The Server saves inside the `:saving` phase, after validation and before the
reply. Reads stay available. New Turns wait.

If the write fails, times out, or returns an uncertain result, the activation
stops. The caller gets no success, and no hooks or Directives run. A timeout
is reported as an unknown outcome: stopping a local task cannot undo a remote
write that already landed. On the next start, `:restore` reads storage and
uses whatever revision is there.

The Server never reports a commit that storage did not confirm.

## Flow Turns

A routed Flow with persistence is a durable Turn:

```text
save acceptance with Agent → run step → confirm checkpoint → run next step → …
Flow completes → save candidate Agent and receipt together → reply
```

If the Agent dies during step 6 after steps 1–5 confirmed their checkpoints,
recovery runs step 6 again. It never resumes inside an Action, so I/O in step 6
can repeat. Steps 1–5 do not run again.

A Flow can wait for a Signal or a timer. While it waits, no worker process
runs. The wait ID and absolute deadline are saved, survive hibernation, and
are restored by `thaw/3`. Other state-changing Turns queue until the Flow
finishes. [Durable Turns and Flows](durable-turns-and-flows.livemd) shows the
full cycle.

Direct Action routes keep the ordinary contract: one write at commit, no
acceptance record, no step checkpoints.

## What Jido Never Replays

- **Post-commit work.** Plugin `after_commit/3` hooks and Directives run once,
  after the reply. If the activation dies mid-batch, recovery does not run them
  again.
- **Caller replies.** A Pending handle or `call/3` wait dies with the Server.
  The caller gets an exit or `{:error, ...}`, even when the Turn committed.
- **Duplicate Signals.** A repeated Signal is a new Turn. Jido does not
  deduplicate by Signal ID.
- **Ordinary context.** Caller `context:` is passed to one execution and is not
  stored. A Flow Turn stores its context in the receipt, so it must be portable.

[Recovery Limits](recovery-and-effect-limits.md) covers designs that tolerate
these gaps.

## Two Kinds Of Checkpoint

| | Activation checkpoint | Adapter record |
| --- | --- | --- |
| Where | ETS owned by the activation supervisor | Your storage backend |
| Written | After every commit | After every commit, before the reply |
| Survives a worker crash | Yes | Yes |
| Survives activation loss | No | Yes |
| Survives a BEAM restart | No | Depends on the adapter |
| Requires configuration | No | Yes |

Without persistence, the activation checkpoint lets a crashed worker restart
from its last commit. With persistence, worker recovery reloads storage, which
can be ahead of the local checkpoint.

The built-in ETS adapter survives activation loss but not a BEAM restart. Use
it for development and tests. [Persistence Adapters](persistence-adapters.livemd)
compares the others.

## Single-Writer Limits

Revision checks stop a stale writer from overwriting newer data. They are not a
writer lease:

- One live Server per `{namespace, partition, id}` is enforced on one node,
  through the instance Registry.
- Jido does not prevent a second node from starting the same Agent against the
  same storage. Each node's Server writes until the other's write moves the
  revision; the loser then stops with a conflict.
- An application that runs Jido on several nodes owns placement: route each
  Agent ID to one node.

## Next

- [Make an Agent Durable](make-an-agent-durable.livemd) to configure an adapter
  and restore an Agent.
- [Durable Activation](durable-agent-activation.livemd) for hibernate, thaw,
  Refs, and deletion.
- [Durable Turns and Flows](durable-turns-and-flows.livemd) for waits and Flow
  recovery.
