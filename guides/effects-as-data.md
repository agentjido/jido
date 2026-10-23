# Effects as Data

This guide maps the functional-effect style, where code returns a
description of an effect and a runtime decides when to run it, to Jido. It
covers Actions that return Directives, the two runtimes that read them,
failures as values, supplied dependencies, owned concurrency, declared
retries and timeouts, and where Jido differs from a general effect system.

> #### Learn Elixir first {: .tip}
>
> This guide assumes you can read basic Elixir. The official guides cover it:
> [Introduction](https://hexdocs.pm/elixir/introduction.html),
> [Pattern matching](https://hexdocs.pm/elixir/pattern-matching.html),
> [Processes](https://hexdocs.pm/elixir/processes.html), and
> [Keyword lists and maps](https://hexdocs.pm/elixir/keywords-and-maps.html).

An Action that registers a user returns the next state and a request to
announce it. It sends nothing:

```elixir
{:ok, %{state | users: [email | state.users]},
 [emit("user.registered", %{email: email})]}
```

`cmd/3` hands that request back as a `%Jido.Agent.Directive.Emit{}` struct.
A live Agent Server commits the state, replies, then sends the Signal.

## Describe, Then Run

In TypeScript you can keep a decision pure by returning tagged objects and
interpreting them later:

```typescript
type State = { users: string[] };
type Effect = { tag: "http"; method: "POST"; url: string; body: unknown };

// Decide: the next state, plus a description of the call
function register(state: State, email: string): [State, Effect[]] {
  return [
    { users: [email, ...state.users] },
    [{ tag: "http", method: "POST", url: "/welcome", body: { email } }],
  ];
}

// Run: the interpreter performs each description
async function interpret(effects: Effect[]): Promise<void> {
  for (const effect of effects) {
    await fetch(effect.url, { method: effect.method, body: JSON.stringify(effect.body) });
  }
}
```

In Jido the decision is an Action, the description is a Directive, and the
interpreter is the Agent Server:

```elixir
defmodule Guides.Signup do
  use Jido.Agent, name: "signup"

  state do
    schema(Zoi.object(%{users: Zoi.list(Zoi.string()) |> Zoi.default([])}))
  end

  routes do
    signal_source("/guides/effects-as-data")

    route "user.register", as: :register do
      action %{email: email},
        name: "register",
        schema: Zoi.object(%{email: Zoi.string()}),
        output_schema: Zoi.map(), context: context do
        state = context.agent_state

        if email in state.users do
          {:error, Jido.Action.Error.execution_error("already registered", %{code: :taken})}
        else
          {:ok, %{state | users: [email | state.users]},
           [emit("user.registered", %{email: email})]}
        end
      end
      state from: output()
    end

    route "user.register_now", as: :register_now do
      action %{email: email, to: to},
        name: "register_now",
        schema: Zoi.object(%{email: Zoi.string(), to: Zoi.any()}),
        output_schema: Zoi.map(), context: context do
        send(to, {:welcome, email})
        state = context.agent_state

        if email in state.users do
          {:error, Jido.Action.Error.execution_error("already registered", %{code: :taken})}
        else
          {:ok, %{state | users: [email | state.users]}}
        end
      end
      state from: output()
    end

    route "user.audit", as: :audit do
      action %{}, name: "audit", schema: Zoi.object(%{}), output_schema: Zoi.map(), context: context do
        {:ok, context.agent_state,
         [emit("user.audited", %{agent: context.agent_id, request: context.request_id})]}
      end
      state from: output()
    end
  end
end

{:ok, _} = Jido.start()
{:ok, signup} = Jido.start_agent(Guides.Signup, id: "signup-1", default_dispatch: {:pid, target: self()})

{:ok, agent, [%Jido.Agent.Directive.Emit{}]} =
  Jido.AgentServer.call(signup, Guides.Signup.register_signal!(%{email: "ada@example.com"}))

agent.state.users
# => ["ada@example.com"]

receive do
  {:signal, signal} -> {signal.type, signal.data}
end
# => {"user.registered", %{email: "ada@example.com"}}
```

`emit/2` builds a full Signal envelope with an ID and the Agent's
`signal_source`. The Server picks the destination at run time. Here
`default_dispatch:` sends it to the test process as `{:signal, signal}`.
[Life of a Signal](signal-to-effects.md) lists the destination order.

Where the analogy breaks:

- The Action doesn't call an interpreter. The Server runs the batch after it
  commits the state, never before.
- The `call/3` reply confirms the commit. The Directive may still be running.
  Read its result from `status/2` as `last_effect_outcome`:
  `%{status: :succeeded, stage: :directive, total: 1, completed: 1, committed_version: 1, ...}`.
- A Directive returns nothing to the Action. To act on its result, deliver a
  Signal back to the Agent as a new Turn.

## Decisions vs Effects

Jido doesn't enforce purity. An Action can call any function, and that call
runs when the Action runs. `register_now` sends the welcome message itself,
then checks for a duplicate:

```elixir
Jido.AgentServer.call(signup, Guides.Signup.register_now_signal!(%{email: "ada@example.com", to: self()}))
# => {:error, %Jido.Action.Error.ExecutionFailureError{message: "already registered", details: %{code: :taken}, ...}}

receive do
  message -> message
end
# => {:welcome, "ada@example.com"}
```

The Turn failed and the state didn't change, but the message was already
sent. Jido can't undo it. The same send also happens under `cmd/3`, which
has no Server at all.

| Put it in | When |
| --- | --- |
| The Action | The next state depends on the result: a price lookup, a model reply. Make it idempotent. |
| A Directive | The work reports what happened, or must not happen unless the state commits. |
| A Directive | You want tests to see the work without running it. |
| A Plugin-owned Directive | Infrastructure must own delivery, such as an outbox. |

[State and Directives](agent-results-and-directives.md) covers every result
shape and built-in Directive.

## Two Runtimes

`cmd/3` is the test runtime. It runs the same route, Action, and validation
as the Server, then returns the Directives as data instead of running them.

In TypeScript, you test the description with a fake interpreter that records
instead of fetching:

```typescript
const performed: Effect[] = [];

async function recordOnly(effects: Effect[]): Promise<void> {
  performed.push(...effects);
}

const [next, effects] = register({ users: [] }, "ada@example.com");
void recordOnly(effects);
// next.users: ["ada@example.com"]
// performed:  [{ tag: "http", method: "POST", url: "/welcome", body: { email: "ada@example.com" } }]
```

In Jido you need no fake. Assert on what `cmd/3` returns:

```elixir
test "register announces the new user" do
  agent = Guides.Signup.instantiate!(id: "signup-test")
  signal = Guides.Signup.register_signal!(%{email: "ada@example.com"})

  assert {:ok, next, [%Jido.Agent.Directive.Emit{signal: emitted, dispatch: nil}]} =
           Guides.Signup.cmd(agent, signal)

  assert next.state.users == ["ada@example.com"]
  assert {emitted.type, emitted.data} == {"user.registered", %{email: "ada@example.com"}}
  assert agent.state.users == []
end
```

`cmd/3` starts no process and leaves the input Agent unchanged. A candidate
is a valid instance, so you can pass `next` to the next `cmd/3` call or to
`Jido.start_agent/2`.

Where the analogy breaks:

- `cmd/3` runs your Action code as written. `register_now` still sends its
  message in a test. Only Directives become data.
- Each `emit/2` gets a new Signal `id`. Match `type` and `data`, not the
  whole struct.
- `cmd/3` skips `admit/3`, `after_commit/3`, persistence, and the rule that
  `server_stop` must be last. Test those against a live Server.

[Pure or Live Execution](pure-or-live-execution.md) compares both runtimes in
full.

## Errors in the Result

A failure is a value in the result, as an effect system would return it. A
failed Turn guarantees three things: no commit, no `after_commit/3` hooks, and
no Directives.

```elixir
Jido.AgentServer.call(signup, Guides.Signup.register_signal!(%{email: "ada@example.com"}))
# => {:error, %Jido.Action.Error.ExecutionFailureError{message: "already registered", details: %{code: :taken}, ...}}

status = Jido.AgentServer.status(signup)
{status.state_version, status.last_outcome.status, status.last_outcome.directive_count}
# => {1, :failed, 0}
```

No `{:signal, _}` message arrives, because the `emit/2` in that branch was
never returned. Match on `details.code`, not the message text.
[Errors and Async](errors-and-async.md) lists every error shape and the
failures that exit the caller instead.

## Supplied Dependencies

An Action doesn't import a global client or read module state. It gets what
it needs from its arguments: the params, and a context map with five reserved
keys plus your caller data.

| Source | Reaches the Action as |
| --- | --- |
| The Agent | `agent_id`, `agent_state`, `agent_topology` |
| The Signal | `signal`, and its data as params |
| Plugins | `plugin_inputs[Plugin].prepared` from `prepare/2`, `plugin_inputs[Plugin].runtime` from `admit/3` |
| The caller | Any key you pass in `context:` |

```elixir
agent = Guides.Signup.instantiate!(id: "signup-1")

{:ok, _, [%{signal: audited}]} =
  Guides.Signup.cmd(agent, Guides.Signup.audit_signal!(), context: %{request_id: "req-7"})

audited.data
# => %{agent: "signup-1", request: "req-7"}

Guides.Signup.cmd(agent, Guides.Signup.audit_signal!(), context: %{agent_id: "other"})
# => {:error, %Jido.Error.ValidationError{message: "Agent command context contains reserved keys", details: %{keys: [:agent_id]}, ...}}
```

`call/3`, `cast/3`, and `submit/3` take the same `context:` option. Caller
context isn't stored in state or in the Signal.

Long-lived resources, such as a connection pool, belong to a Plugin runtime.
The activation starts it, and `admit/3` and `dispatch/4` receive its
reference. [Supervised Resources](plugin-supervised-resources.livemd) builds
one. The Jido instance supplies the Registry, task supervisor, and runner;
see [Instances and Tenants](configuration-and-tenant-isolation.md).

## Owned Concurrency

Each Turn runs in a worker the Server owns. Processes linked to that worker
stop with it. When a Turn passes `turn_timeout:`, a `Task` its Action
started stops too:

```elixir
{:ok, short} = Jido.start_agent(Guides.Signup, id: "short", turn_timeout: 100)
```

With a 300 ms `Task.async/1` inside the Action, the call returns
`{:error, :turn_timeout}`, the Task is dead, and its final message never
arrives. `cancel/2` stops owned work the same way.

The ownership continues up the tree:

- The activation supervisor is `:one_for_all`. If the Server or a required
  Plugin runtime crashes, they restart together.
- Plugin runtimes start with the activation and stop with it.
- `Jido.stop_agent/2` stops the activation and its nested Agents.

Work outside this tree isn't owned. `ProcessStart` starts a child under the
instance, and it can outlive the Server. A Task that you don't link isn't
stopped. [Supervision and Lifecycle](agent-activation-control.md) covers
restarts and stops.

## Policies, Not Loops

In TypeScript you write the retry loop:

```typescript
async function withRetry<T>(run: () => Promise<T>, attempts: number): Promise<T> {
  for (let i = 1; ; i++) {
    try {
      return await run();
    } catch (err) {
      if (i >= attempts) throw err;
      await new Promise((resolve) => setTimeout(resolve, 10 * 2 ** i));
    }
  }
}
```

In Jido you declare the policy when you start the Agent, and the Action
marks which errors are safe to retry:

```elixir
{:ok, worker} =
  Jido.start_agent(Guides.Signup,
    id: "signup-2",
    turn_timeout: 10_000,
    exec_opts: [timeout: 2_000, max_attempts: 3, backoff: :exponential, base_delay_ms: 10],
    directive_timeout: 5_000
  )

# In the Action:
{:error, Jido.Action.Error.execution_error("upstream busy", %{retry: true})}
```

An Action that fails twice with `retry: true` and then succeeds returns
`{:ok, agent, directives}` from one `call/3`, after three attempts. Without
`exec_opts:` the same call fails after one attempt.

| Option | Where | Default | Bounds |
| --- | --- | --- | --- |
| `admission_timeout:` | `call/3`, `submit/3` | 5,000 ms | Wait before the Turn starts |
| `turn_timeout:` | Start | 60,000 ms | All pre-commit work, retries included |
| `exec_opts: [timeout:]` | Start | none | One attempt of one Action or Flow node |
| `exec_opts: [max_attempts:]` | Start | `1` | Total attempts per node |
| `exec_opts: [backoff:]` | Start | none | `:linear`, `:exponential`, or `:jitter` |
| `directive_timeout:` | Start | 5,000 ms | The whole Directive batch |

Where the analogy breaks: a retry happens only when
`Jido.Action.Error.retryable?/1` returns `true`, which needs `retry: true` in
the error details. Plain errors, invalid input, and raised exceptions never
retry. Directives never retry. An unknown `exec_opts:` key fails startup with
`"invalid exec_opts"`. [Admission and Deadlines](agent-server-admission.md)
covers each limit and its result.

## Where Jido Differs

- **A fixed boundary.** A general effect description runs wherever you hand
  it to an interpreter. Jido runs Directives at one point: after the
  candidate state validates and commits, in order, before the next Turn.
- **Impure Actions are allowed.** Purity is your choice per Action.
  Inline I/O runs before commit and under `cmd/3`, and a failed Turn doesn't
  undo it.
- **The runtime is the VM.** Each Agent is a process with its own heap,
  preemptive scheduling, and a supervisor. Your Action never yields.
  [Node.js and the BEAM](nodejs-and-the-beam.md) covers the runtime.
- **No rollback after commit.** A Directive that fails or times out stops the
  rest of the batch, and the commit stands. The caller already has `:ok`. A
  Signal sent to a dead pid fails with no log entry; only
  `last_effect_outcome` in `status/2` shows it.
  [Recovery Limits](recovery-and-effect-limits.md) covers what survives.
- **You add effect types.** A custom Directive is a struct a Plugin owns and
  runs in `dispatch/4`. `cmd/3` returns it as data like any built-in one.
  [Custom Directives](plugin-custom-directives.livemd) builds one.

```elixir
:ok = Jido.stop()
```

## Next

- [OTP Concepts](otp-concepts-for-jido.md) for processes, supervisors, and
  messages in Jido terms.
- [Life of a Signal](signal-to-effects.md) for each stage of a Turn and its
  failure rule.
