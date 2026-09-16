# Agent Server controls

Start the default instance with `Jido.start/1`, or define a supervised module
that uses `Jido`. `Jido.start/1` returns the running instance on a later call;
only the first successful call applies its options. A later call cannot change
the namespace or persistence source. Call
`Jido.start_agent(MyAgent, id: id, initial_state: state)`
for the default instance. Pass an instance as the first argument only when you
use more than one Jido supervisor. The live API accepts a PID.
`Jido.whereis_agent/1` resolves an ID in the default instance. Options select a
partition. It returns only a Server that completed Plugin readiness and any
required revision-zero write. A second local registration for that identity
fails, including while the first process has only reserved the identity.

Use `AgentServer.agent/1` for current Agent data, `snapshot/1` for the Agent and
commit revision, `status/1` for execution and queue status, and `children/1` for
owned child information. The Server is a `:gen_statem`; the old GenServer
state shape is removed. Do not read it through an old State struct contract.

`send_request/3` and `receive_response/2` separate sending from waiting.
`cancel/1` and `cancel_turn/2` cancel eligible pre-commit work. They do not roll
back an external effect, a completed commit, or directive work.

`turn_timeout` limits active pre-commit work from Plugin admission until commit
starts. Its default is 5 seconds. A timeout stops owned admission or execution,
keeps the committed snapshot, and rejects late results. Caller wait time and
post-commit Directive time use separate limits.

`attach/2` monitors an owner and prevents idle shutdown. Repeated attachment of
one owner is idempotent. `detach/2` or owner death removes the attachment.
The last removal starts the configured idle timer. `touch/1` resets that timer.
`idle_timeout` defaults to `:infinity`. Idle shutdown removes the registration.
These controls remain; the old InstanceManager facade and worker-pool API do not.

## Use a stable Agent Ref

Add a namespace to a generated Jido instance when a logical Agent identity
must stay stable across local Supervisor names and PIDs:

```elixir
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app, namespace: "my-app/primary"
end

{:ok, ref} = MyApp.Jido.agent_ref("agent-42", partition: "north")
{:ok, _server} = MyApp.Jido.start_agent_ref(ref, MyAgent)
{:ok, agent} = MyApp.Jido.call(ref, signal)
```

The Ref facade also provides cast and OTP request functions, cancellation,
attach and detach controls, stop and hibernate functions, durable activation
and delete, and Server inspection. Each operation validates the Ref namespace
and resolves its current local PID. A missing Agent returns
`{:error, :not_found}`. A namespace is local identity input. It does not prove
remote location or write authority.

Use `Jido.stop_agent/1` to stop an Agent. Use `hibernate/1` and `thaw/2` when
persistence is configured. Each function also accepts an explicit instance.
See [storage](storage.md) and `Jido.AgentServer` for owned children.
