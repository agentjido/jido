# Agent Server controls

Start an instance with `Jido.start/1` or a supervised module that uses `Jido`.
Call `Jido.start_agent(instance, MyAgent, id: id, initial_state: state)`.
The live API accepts a PID. `Jido.whereis_agent/3` resolves an ID in its instance
and partition. A second local registration for that identity fails.

Use `AgentServer.agent/1` for current Agent data, `snapshot/1` for the Agent and
commit revision, `status/1` for execution and queue status, and `children/1` for
owned child information. The Server is a `:gen_statem`; the old GenServer
state shape is removed. Do not read it through an old State struct contract.

`send_request/3` and `receive_response/2` separate sending from waiting.
`cancel/1` and `cancel_turn/2` cancel eligible pre-commit work. They do not roll
back an external effect, a completed commit, or directive work.

`attach/2` monitors an owner and prevents idle shutdown. Repeated attachment of
one owner is idempotent. `detach/2` or owner death removes the attachment.
The last removal starts the configured idle timer. `touch/1` resets that timer.
`idle_timeout` defaults to `:infinity`. Idle shutdown removes the registration.
These controls remain; the old InstanceManager facade and worker-pool API do not.

Use `Jido.stop_agent/3` to stop an Agent. Use `hibernate/3` and `thaw/4` when
persistence is configured. See [storage](storage.md) and `Jido.AgentServer` for owned children.
