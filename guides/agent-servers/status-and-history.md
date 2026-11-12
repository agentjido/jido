# AgentServer Status and Snapshots

`Jido.AgentServer.status/2` returns semantic runtime state. It contains no PID,
port, reference, callback, timer, task, or Runic value. Use it for control
logic, logs, and dashboards.

`Jido.AgentServer.snapshot/2` returns the complete committed Agent value and
its revisions from the same server event.

## Status fields

`Jido.AgentServer.Status` separates three state axes:

| Field | Values | Meaning |
| --- | --- | --- |
| `lifecycle` | `:alive`, `:deleted` | Logical Agent life. |
| `work_state` | `:idle`, `:running`, `:waiting`, `:faulted` | Current work. |
| `residency` | `:passivated`, `:activating`, `:active`, `:passivating` | Process residency. |

It also reports:

- `agent_ref` and `agent_activation_id`
- `ready?` and `durability`
- `agent_revision` and `persistence_revision`
- `admission` and `queue_depth`
- `active_turn_id`, `waits`, `last_outcome`, and `effects`

The old `phase`, `active`, `state_version`, `durable_turn`, history, and effect
detail maps are not public AgentServer fields.

## Read a resident activation

```elixir
status = Jido.AgentServer.status(server)

%Jido.AgentServer.Status{
  lifecycle: :alive,
  residency: :active,
  ready?: true,
  admission: :open
} = status

snapshot = Jido.AgentServer.snapshot(server)

%Jido.AgentServer.Snapshot{
  agent: %Jido.Agent{},
  agent_revision: agent_revision,
  persistence_revision: persistence_revision
} = snapshot
```

For an in-memory Agent, `persistence_revision` is `nil`. A durable operation
can change the persistence revision without changing the Agent revision. The
two fields are intentionally separate.

## Read a durable logical Agent

Use `Jido.status/3` with a stable `Jido.Agent.Ref`. The Instance can return a
passivated status even when no AgentServer process is resident.

```elixir
%Jido.AgentServer.Status{
  lifecycle: :alive,
  work_state: :idle,
  residency: :passivated,
  ready?: false
} = Jido.status(MyApp.Jido, agent_ref)
```

Use `Jido.activate_agent/3` when you need a direct AgentServer handle. Ref
Signal operations activate the Agent when required.

## Inspect one accepted Turn

`call/3` and `await/2` return a process-neutral `TurnResult` for accepted work.

```elixir
{:ok, %Jido.AgentServer.TurnResult{status: :committed} = result} =
  Jido.AgentServer.call(server, signal)

{result.turn_id, result.agent_revision, result.persistence_revision}
```

An accepted failure is also a `TurnResult`:

```elixir
{:ok, %Jido.AgentServer.TurnResult{status: :failed, error: reason}} =
  Jido.AgentServer.call(server, invalid_signal)
```

`{:error, reason}` means that the runtime did not accept the work or that the
transport failed.
