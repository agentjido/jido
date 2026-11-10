# Parent and Child Agents

Use this guide when a Turn or a caller decides that work needs its own Agent process. It shows how to start a child, exchange Signals with it, stop it, and choose what happens when its parent exits.

For collaborators that the definition always includes, use [Declare Agent Topology](declare-agent-topology.livemd).

## Start a child from a Turn

An Action returns `Jido.AgentServer.Directive.agent_start/3` with the child's module and a tag. The tag is an atom or a string. Then `Jido.Agent.Directive.agent_send/2` sends the child a Signal by that tag.

AgentServer commits the state first and runs the Directives in order after the commit. `agent_start/3` waits for the child to be ready, so a send in the same batch reaches it. Keep your own record of intent in Agent state, and let AgentServer track the PIDs.

```elixir
defmodule ChildGuide.Summarizer do
  use Jido.Agent, name: "ticket_summarizer"

  state do
    schema Jido.Joi.object(%{handled: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/tickets/summarizer"

    route "ticket.summarize", as: :summarize do
      action %{request_id: request_id, words: words},
        schema: Jido.Joi.object(%{request_id: Jido.Joi.string(), words: Jido.Joi.integer()}),
        context: context do
        result =
          Jido.Signal.new!(
            "ticket.summarized",
            %{request_id: request_id, words: div(words, 2)},
            source: "/tickets/summarizer"
          )

        {:ok, %{handled: context.agent_state.handled + 1},
         [Jido.Agent.Directive.parent_send(result)]}
      end
    end
  end
end

defmodule ChildGuide.Triage do
  use Jido.Agent, name: "ticket_triage"

  alias Jido.Agent.Directive
  alias Jido.AgentServer.Directive, as: RuntimeDirective

  state do
    schema Jido.Joi.object(%{
             pending: Jido.Joi.string() |> Jido.Joi.nullable() |> Jido.Joi.default(nil),
             summary_words: Jido.Joi.integer() |> Jido.Joi.default(0)
           })
  end

  routes do
    signal_source "/tickets/triage"

    route "ticket.opened", as: :open do
      action %{request_id: request_id, words: words},
        schema: Jido.Joi.object(%{request_id: Jido.Joi.string(), words: Jido.Joi.integer()}),
        context: context do
        {:ok, work} =
          ChildGuide.Summarizer.summarize_signal(%{request_id: request_id, words: words})

        {:ok, %{context.agent_state | pending: request_id},
         [
           RuntimeDirective.agent_start(ChildGuide.Summarizer, request_id),
           Directive.agent_send(request_id, work)
         ]}
      end
    end

    route "ticket.summarized" do
      action %{request_id: request_id, words: words},
        schema: Jido.Joi.object(%{request_id: Jido.Joi.string(), words: Jido.Joi.integer()}),
        context: context do
        if request_id == context.agent_state.pending do
          {:ok, %{context.agent_state | pending: nil, summary_words: words},
           [RuntimeDirective.agent_stop(request_id)]}
        else
          {:error, Jido.Error.validation_error("result is stale or unrelated")}
        end
      end
    end
  end
end
```

## Run it

A pure `cmd` call plans the Directives and starts nothing. A live call runs them.

```elixir
wait_until = fn check ->
  Enum.find(1..200, fn _attempt ->
    check.() || (Process.sleep(10) && false)
  end) != nil
end

{:ok, _instance} = Jido.start(name: ChildGuide.Jido)
{:ok, triage} = Jido.start_agent(ChildGuide.Jido, ChildGuide.Triage, id: "triage-1")

{:ok, opened} = ChildGuide.Triage.open_signal(%{request_id: "ticket-42", words: 300})

{:ok, _planned, [%Jido.AgentServer.Directive.AgentStart{name: "ticket-42"}, _send]} =
  ChildGuide.Triage.cmd(Jido.AgentServer.agent(triage), opened)

true = Jido.AgentServer.children(triage) == %{}

{:ok, _committed, _directives} = Jido.AgentServer.call(triage, opened)
true = wait_until.(fn -> Jido.AgentServer.agent(triage).state.summary_words == 150 end)
true = wait_until.(fn -> Jido.AgentServer.children(triage) == %{} end)
```

The parent receives the result in a later Turn, commits it, and stops the child. The result carries the request ID so the parent can reject a stale or unrelated reply. Jido does not correlate results for you.

## Choose the Agent and its options

`agent_start/3` takes these options. Unknown or duplicate options raise `ArgumentError`.

| Option | Default | Meaning |
| --- | --- | --- |
| `:restart` | `:transient` | OTP restart policy: `:permanent`, `:transient`, or `:temporary`. |
| `:opts` | `%{}` | Map or keyword list with instance `:id` and `:state`, plus AgentServer options. |
| `:meta` | `%{}` | Map or keyword list that appears in the child's `parent` status. |
| `:node` | `nil` | Must be `nil` or the local node. A remote node fails with `:remote_agent_start_not_supported`. |

The child ID defaults to `"<parent id>/<tag>"`. The first argument can also be a complete Agent instance, which supplies its own ID and state and so cannot be combined with `:id` or `:state` in `:opts`. A child started this way does not inherit the parent's persistence.

## Read a child

`Jido.AgentServer.children/2` returns a map from tag to `pid`, `activation`, and `placement`. A child sees its parent through `Jido.AgentServer.status/1`.

```elixir
worker = ChildGuide.Summarizer.instantiate!(id: "summarizer-read")
{:ok, child} = Jido.AgentServer.spawn_child(triage, worker, :reader, meta: %{queue: "billing"})
:ok = Jido.AgentServer.await_ready(child)

%{reader: %{pid: ^child, placement: :owned}} = Jido.AgentServer.children(triage)
%{agent_id: "triage-1", tag: :reader, meta: %{queue: "billing"}} = Jido.AgentServer.status(child).parent

:ok = Jido.AgentServer.stop_child(triage, :reader)
```

`Jido.AgentServer.spawn_child/4` does the same work as the Directive, for a caller outside a Turn. It takes a complete instance and returns `{:ok, pid}`.

## Failures of a child Directive

Target checks run before commit. A Turn that starts or stops a topology member's name, or uses a reserved `$topology/` name, fails and commits nothing.

Other failures happen after commit, and the commit stands. These include a tag already in use, a send or stop for an unknown tag, and a child that fails to start. The parent keeps running and `last_effect_outcome` records the failure.

```elixir
defmodule ChildGuide.Sender do
  use Jido.Agent, name: "ticket_sender"

  routes do
    signal_source "/tickets/sender"

    route "ticket.forward", as: :forward_ticket do
      action %{tag: tag}, schema: Jido.Joi.object(%{tag: Jido.Joi.string()}), context: context do
        {:ok, work} = ChildGuide.Summarizer.summarize_signal(%{request_id: "r", words: 2})
        {:ok, context.agent_state, [Jido.Agent.Directive.agent_send(tag, work)]}
      end
    end
  end
end

{:ok, sender} = Jido.start_agent(ChildGuide.Jido, ChildGuide.Sender, id: "sender-1")
{:ok, forward} = ChildGuide.Sender.forward_ticket_signal(%{tag: "no-such-child"})
{:ok, _committed, _directives} = Jido.AgentServer.call(sender, forward)

true = wait_until.(fn ->
  match?(%{status: :failed}, Jido.AgentServer.status(sender).last_effect_outcome)
end)
```

Jido sends the parent no Signal when a child starts or exits. To learn that a child stopped, have it report through `parent_send/1` first, or monitor its PID from a process outside the Agent. `Jido.AgentServer.children/2` shows only live children.

## Restart behavior

A child is a complete activation with its own worker. When the worker crashes, it restarts inside that activation under every policy. It keeps its committed state and its tag, and has a new PID.

```text
owner activation -> owned children supervisor -> child activation -> child worker
```

`:restart` applies when the child's activation itself exits. An activation restart begins again from the instance the child started with, so committed state is lost.

| Policy | Worker exits with `:normal` or `:shutdown` | Activation crashes |
| --- | --- | --- |
| `:temporary` | Removed from `children/2` | Removed |
| `:transient` | Removed from `children/2` | Restarts |
| `:permanent` | Restarts | Restarts |

An activation allows 3 worker restarts in 5 seconds. Past that limit, a `:temporary` or `:transient` child is removed and its parent keeps running. A `:permanent` child restarts again, and repeated crashes can exceed the limit of the parent's supervisor and stop the parent too. `Jido.AgentServer.stop_child/3` removes the child under every policy.

```elixir
worker = ChildGuide.Summarizer.instantiate!(id: "summarizer-restart")
{:ok, child} = Jido.AgentServer.spawn_child(triage, worker, :steady)
:ok = Jido.AgentServer.await_ready(child)

{:ok, work} = ChildGuide.Summarizer.summarize_signal(%{request_id: "steady", words: 8})
{:ok, %{state: %{handled: 1}}, _directives} = Jido.AgentServer.call(child, work)

Process.exit(child, :kill)

true = wait_until.(fn ->
  case Jido.AgentServer.children(triage) do
    %{steady: %{pid: pid}} when pid != child -> true
    _other -> false
  end
end)

%{steady: %{pid: restarted}} = Jido.AgentServer.children(triage)
1 = Jido.AgentServer.agent(restarted).state.handled
```

An owned child depends on its parent's activation. When the parent's worker crashes, the activation restarts as a group, the owned children stop, and they do not come back. Only your Agent state remembers them, so start them again from a Signal if you still need them. Declared members do return. See [Topology Reconciliation](topology-reconciliation.md).

```elixir
activation = Jido.AgentServer.activation(triage)
Process.exit(triage, :kill)

true = wait_until.(fn ->
  case Jido.AgentServer.worker(activation) do
    pid when is_pid(pid) and pid != triage -> Process.alive?(pid)
    _other -> false
  end
end)

new_triage = Jido.AgentServer.worker(activation)
:ok = Jido.AgentServer.await_ready(new_triage)
true = Jido.AgentServer.children(new_triage) == %{}
false = Process.alive?(restarted)
```

## Let a child outlive its parent

An owned child always stops with its parent. Pass `placement: :independent` to `spawn_child/4` to run the child under the instance supervisor, then choose a policy with `:on_parent_exit`.

| Policy | When the parent's activation exits |
| --- | --- |
| `:stop` (default) | The child stops. |
| `:continue` | The child keeps running with no parent. |
| `:emit_orphan` | The child keeps running and sends `jido.agent_server.orphaned` to `:orphan_dispatch`. |

```elixir
{:ok, shift_lead} = Jido.start_agent(ChildGuide.Jido, ChildGuide.Triage, id: "shift-lead")
worker = ChildGuide.Summarizer.instantiate!(id: "summarizer-free")

{:ok, free} =
  Jido.AgentServer.spawn_child(shift_lead, worker, :free,
    placement: :independent,
    on_parent_exit: :emit_orphan,
    orphan_dispatch: {:pid, target: self()}
  )

:ok = Jido.stop_agent(ChildGuide.Jido, shift_lead)

orphaned =
  receive do
    {:signal, %{type: "jido.agent_server.orphaned"} = signal} -> signal.data
  after
    2_000 -> :timeout
  end

%{parent_id: "shift-lead", tag: :free} = orphaned
true = wait_until.(fn -> Jido.AgentServer.status(free).parent == nil end)
```

Another Agent in the same instance and partition can take over the orphan with `Jido.AgentServer.adopt_child/4`. See [Child Agent Adoption](../agent-servers/child-agents-and-adoption.md).

```elixir
:ok = Jido.stop_agent(ChildGuide.Jido, free)
:ok = Jido.stop_agent(ChildGuide.Jido, sender)
:ok = Jido.stop_agent(ChildGuide.Jido, new_triage)
```

## `spawn_child/4` options and errors

The options are `:placement`, `:on_parent_exit`, `:orphan_dispatch`, `:restart`, `:server_options`, and `:meta`. `:server_options` sets AgentServer runtime options for the child.

| Error | Cause |
| --- | --- |
| `:invalid_child_options` | An unknown or duplicate option, or `:meta` or `:server_options` with an invalid value. |
| `:invalid_child_tag` | The tag is `nil` or is not an atom or string. |
| `:tag_in_use` | The parent already tracks this tag. |
| `:invalid_placement` | `:placement` is not `:owned` or `:independent`. |
| `:invalid_parent_policy` | `:on_parent_exit` is not one of the three policies. |
| `:owned_child_cannot_survive_parent` | An owned child asked for a policy other than `:stop`. |
| `:invalid_orphan_dispatch` | `:emit_orphan` without a valid `:orphan_dispatch`. |
| `:invalid_restart_policy` | `:restart` is not an OTP restart value. |
| `:activation_required` | The parent is a bare worker with no activation. |
| `:jido_instance_required` | An independent child needs a parent that belongs to a Jido instance. |

`Jido.AgentServer.stop_child/3` returns `{:error, :child_not_found}` for an unknown tag.

## Related

- [Composition Vocabulary](composition-vocabulary.md) compares runtime children with declared members.
- [Runtime Effects](../agent-servers/runtime-directives-and-effects.md) covers how AgentServer runs Directives after commit.
