# Agent Server Lifecycle

`Jido.AgentServer` is the OTP owner of one live Agent. It uses `:gen_statem` to
keep runtime phases explicit while work runs in supervised tasks.

## Activation

Startup constructs or accepts one Agent instance, applies restore policy, starts
Plugin runtimes, and waits for their readiness checks. `start_link/1` returns
only after the initial bootstrap reply is ready. `await_ready/2` is also
available for callers that receive a Server before all dependent work settles.

Each activation has a new activation ID. A restarted Server can keep the same
Agent ID and state version.

## Runtime Phases

The public status can report initialization, idle work, admission, executable
work, and Directive dispatch. The Server handles one Agent Turn at a time.
It can keep its mailbox responsive while Plugin admission, Jido Action
execution, and Plugin dispatch run in owned tasks.

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
instance or VM restarts.

Use `Jido.stop_agent/3` when the instance owns the Server. Use
`Jido.AgentServer.stop/3` for a direct Server reference. A `Stop` Directive
stops the Server after its current state commit.

## Idle Hibernation

An idle Server with persistence can save and stop through `hibernate/2`. A later
`Jido.thaw/4` loads the checkpoint and starts the Agent again. Hibernation is not
available during active Turn work.

See [Calls, Casts, And Requests](calls-casts-and-requests.livemd),
[Runtime State And Debugging](runtime-state-and-debugging.livemd), and
[Compare And Swap, Hibernate, And Thaw](compare-and-swap-hibernate-and-thaw.md).
