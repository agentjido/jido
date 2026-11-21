# Child Agent Adoption

This guide starts child Agents at runtime, reads and stops them, and moves a surviving child to a new parent. Use it when the set of children depends on live work. To declare a fixed set of members, see [Declare Agent Topology](../composition/declare-agent-topology.livemd).

The examples use a dispatch Agent that assigns work to courier Agents.

```elixir
defmodule ChildGuide.Courier do
  use Jido.Agent, name: "courier"

  state do
    schema Jido.Joi.object(%{delivered: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/couriers"

    route "parcel.deliver", as: :deliver do
      action %{count: count},
        schema: Jido.Joi.object(%{count: Jido.Joi.integer()}),
        context: context do
        total = context.agent_state.delivered + count
        report = Jido.Signal.new!("courier.reported", %{total: total}, source: "/couriers")
        {:ok, %{context.agent_state | delivered: total}, [Jido.Agent.Directive.parent_send(report)]}
      end
    end
  end
end

defmodule ChildGuide.Dispatch do
  use Jido.Agent, name: "dispatch"

  alias Jido.Agent.Directive
  alias Jido.AgentServer.Directive, as: ServerDirective

  state do
    schema Jido.Joi.object(%{last_total: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/dispatch"

    route "courier.hire", as: :hire do
      action %{name: name},
        schema: Jido.Joi.object(%{name: Jido.Joi.string()}),
        context: context do
        {:ok, context.agent_state, [ServerDirective.agent_start(ChildGuide.Courier, name)]}
      end
    end

    route "courier.release", as: :release do
      action %{name: name},
        schema: Jido.Joi.object(%{name: Jido.Joi.string()}),
        context: context do
        {:ok, context.agent_state, [ServerDirective.agent_stop(name)]}
      end
    end

    route "courier.assign", as: :assign do
      action %{name: name, count: count},
        schema: Jido.Joi.object(%{name: Jido.Joi.string(), count: Jido.Joi.integer()}),
        context: context do
        work = Jido.Signal.new!("parcel.deliver", %{count: count}, source: "/dispatch")
        {:ok, context.agent_state, [Directive.agent_send(name, work)]}
      end
    end

    route "courier.reported", as: :reported do
      action %{total: total},
        schema: Jido.Joi.object(%{total: Jido.Joi.integer()}),
        context: context do
        {:ok, %{context.agent_state | last_total: total}}
      end
    end

    route "dispatch.ping", as: :ping do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        {:ok, context.agent_state}
      end
    end
  end
end

{:ok, _instance} = Jido.start(name: ChildGuide.Jido)
{:ok, dispatch} = Jido.start_agent(ChildGuide.Jido, ChildGuide.Dispatch, id: "dispatch-1", idle_timeout: 60_000)
:ok = Jido.AgentServer.await_ready(dispatch)

wait_until = fn check ->
  Enum.find_value(1..200, fn _attempt ->
    Process.sleep(5)
    check.()
  end) || raise "the condition was not met in time"
end
```

## Start a child from a Turn

Return `Jido.AgentServer.Directive.agent_start/3` from an Action when the decision to start a child belongs to the Agent. The child starts after the parent commits. `call/3` returns at commit, and a later Turn on the same server runs after the effect finishes.

```elixir
{:ok, _agent, [%Jido.AgentServer.Directive.AgentStart{name: "ana"}]} =
  Jido.AgentServer.call(dispatch, ChildGuide.Dispatch.hire_signal!(%{name: "ana"}))

{:ok, _agent, []} = Jido.AgentServer.call(dispatch, ChildGuide.Dispatch.ping_signal!(%{}))

%{"ana" => %{pid: ana, activation: _activation, placement: :owned}} =
  Jido.AgentServer.children(dispatch)

%{id: "dispatch-1/ana"} = Jido.AgentServer.snapshot(ana).agent
```

The name is the child's tag in its parent, and it must be an atom or a string. The default child ID is `<parent id>/<tag>`. `agent_start/3` accepts these options:

- `:opts` holds the instance `:id` and `:state`, and AgentServer options. It rejects `:jido`, `:partition`, `:runner`, `:persistence`, and `:idle_timeout`, among others. A child started this way has no persistence.
- `:meta` is a plain Map that appears in the child's parent status.
- `:restart` is an OTP restart policy.
- `:node` must be the local node. Another node fails before commit.

Keep tags or other durable data in Agent state, not PIDs. A PID changes when the child restarts.

## Start a child from outside a Turn

`Jido.AgentServer.spawn_child/4` starts a child at once and returns its worker. Pass a complete Agent instance. Choose the ID, because the parent does not generate one here.

```elixir
courier = ChildGuide.Courier.instantiate!(id: "dispatch-1/ben")

{:ok, ben} = Jido.AgentServer.spawn_child(dispatch, courier, :ben, meta: %{zone: "north"})
:ok = Jido.AgentServer.await_ready(ben)

%{agent_id: "dispatch-1", tag: :ben, placement: :owned, policy: :stop, restart: :transient, meta: %{zone: "north"}} =
  Jido.AgentServer.status(ben).parent
```

A caller timeout does not cancel the startup.

| Option | Default | Meaning |
| --- | --- | --- |
| `:placement` | `:owned` | Where the child's activation runs. |
| `:on_parent_exit` | `:stop` | What an independent child does when its parent stops. |
| `:orphan_dispatch` | None | Where to send the orphan Signal. Required with `:emit_orphan`. |
| `:restart` | `:transient` | The OTP restart policy of the child's activation. |
| `:server_options` | `[]` | AgentServer runtime options for the child. |
| `:meta` | `%{}` | A plain Map, returned in the child's parent status. |

A child inherits its parent's runtime options, including persistence, except where `:server_options` overrides them. It cannot change its Agent identity, OTP name, instance, partition, or Runner.

```elixir
60_000 = Jido.AgentServer.status(ben).idle_timeout

{:ok, cal} =
  Jido.AgentServer.spawn_child(
    dispatch,
    ChildGuide.Courier.instantiate!(id: "dispatch-1/cal"),
    :cal,
    server_options: [idle_timeout: :infinity]
  )

:infinity = Jido.AgentServer.status(cal).idle_timeout
```

## Send Signals between parent and child

A parent sends to a tag with `Jido.Agent.Directive.agent_send/2`. A child sends to its parent with `Jido.Agent.Directive.parent_send/1`. Both are casts: they do not wait for the other Turn, and a failure there only reaches that Agent's logs and status.

```elixir
{:ok, _agent, _directives} =
  Jido.AgentServer.call(dispatch, ChildGuide.Dispatch.assign_signal!(%{name: "ana", count: 3}))

wait_until.(fn -> Jido.AgentServer.snapshot(dispatch).agent.state.last_total == 3 end)
```

The receiving Agent needs a route for the Signal. `parent_send/1` fails before commit with `{:error, :parent_not_found}` in an Agent that has no parent. An `agent_send/2` to an unknown tag commits, then fails as an effect with the outcome in `last_effect_outcome`.

The parent receives no Signal when a child starts or exits. Read `Jido.AgentServer.children/2`, or have the child report through `parent_send/1`.

## Read and stop children

`Jido.AgentServer.children/2` returns live children by tag, each with its worker `:pid`, `:activation`, and `:placement`.

`Jido.AgentServer.stop_child/3` stops the child's whole activation and confirms it, then frees the tag. It returns `{:error, :child_not_found}` for an unknown tag. `Jido.AgentServer.Directive.agent_stop/2` does the same from a Turn.

```elixir
:ok = Jido.AgentServer.stop_child(dispatch, :cal)
{:error, :child_not_found} = Jido.AgentServer.stop_child(dispatch, :cal)

{:ok, _agent, _directives} =
  Jido.AgentServer.call(dispatch, ChildGuide.Dispatch.release_signal!(%{name: "ana"}))

{:ok, _agent, []} = Jido.AgentServer.call(dispatch, ChildGuide.Dispatch.ping_signal!(%{}))

Jido.AgentServer.children(dispatch) |> Map.keys()
```

## Choose placement and lifetime

Placement decides which supervisor runs the child.

| | `placement: :owned` | `placement: :independent` |
| --- | --- | --- |
| Supervisor | The parent's activation. | The instance's Agent supervisor. |
| Parent stops | The child stops. | `:on_parent_exit` decides. |
| Parent's worker restarts | The child stops, and its tag is released. | The child keeps running and stays attached. |
| `:on_parent_exit` | Must be `:stop`. | `:stop`, `:continue`, or `:emit_orphan`. |

`:on_parent_exit` applies when the parent's activation exits:

- `:stop` stops the child with `{:shutdown, :parent_down}`.
- `:continue` leaves the child running with no parent.
- `:emit_orphan` also dispatches a `jido.agent_server.orphaned` Signal to `:orphan_dispatch`. The child stops if that dispatch fails or runs past its `:directive_timeout`.

`:restart` applies when a child's activation exits. A worker crash inside the activation restarts the worker first, with its committed state, under the limit in [Agent Lifecycle](agent-activation-control.md#recover-from-a-crash).

## Adopt an orphan

`Jido.AgentServer.adopt_child/4` attaches a parentless independent child to a new parent in the same instance and partition. The child keeps its process and state.

```elixir
{:ok, old_parent} = Jido.start_agent(ChildGuide.Jido, ChildGuide.Dispatch, id: "dispatch-2")
{:ok, new_parent} = Jido.start_agent(ChildGuide.Jido, ChildGuide.Dispatch, id: "dispatch-3")

{:ok, dana} =
  Jido.AgentServer.spawn_child(
    old_parent,
    ChildGuide.Courier.instantiate!(id: "courier-dana"),
    :dana,
    placement: :independent,
    on_parent_exit: :emit_orphan,
    orphan_dispatch: {:pid, target: self()}
  )

:ok = Jido.AgentServer.await_ready(dana)

{:error, :already_attached} = Jido.AgentServer.adopt_child(new_parent, dana, :dana)

:ok = Jido.stop_agent(ChildGuide.Jido, old_parent)

%{parent_id: "dispatch-2", tag: :dana} =
  receive do
    {:signal, %Jido.Signal{type: "jido.agent_server.orphaned", data: data}} -> data
  after
    1_000 -> raise "no orphan Signal arrived"
  end

wait_until.(fn -> Jido.AgentServer.status(dana).parent == nil end)

:ok = Jido.AgentServer.adopt_child(new_parent, dana, :dana, meta: %{zone: "south"})

%{dana: %{pid: ^dana, placement: :independent}} = Jido.AgentServer.children(new_parent)
%{agent_id: "dispatch-3", policy: :stop} = Jido.AgentServer.status(dana).parent
```

The orphan Signal's data holds `:parent_id`, `:tag`, and a text `:reason`. Its source is `/agent/<child id>`.

Adoption accepts only relationship options: `:on_parent_exit`, `:orphan_dispatch`, `:restart`, and `:meta`. It does not change the child's server options. `:on_parent_exit` returns to `:stop` unless you set it.

## Child errors

| Error | Cause |
| --- | --- |
| `{:error, :tag_in_use}` | The parent already has a child, or a pending start, with this tag. |
| `{:error, :activation_required}` | The parent or the child is a bare worker. |
| `{:error, :owned_child_cannot_survive_parent}` | An owned child has an `:on_parent_exit` other than `:stop`. |
| `{:error, :invalid_orphan_dispatch}` | `:emit_orphan` has a missing or invalid dispatch. |
| `{:error, :invalid_child_tag}`, `:invalid_placement`, `:invalid_parent_policy`, `:invalid_restart_policy`, `:invalid_child_options` | An option is invalid. |
| `{:error, {:shutdown, {:failed_to_start_child, Jido.AgentServer, {:already_started, pid}}}}` | The child's ID is already live in this instance and partition. |
| `{:error, :already_attached}` | The child still has a parent. |
| `{:error, :orphan_dispatch_pending}` | The orphan Signal is still being sent. Retry. |
| `{:error, :different_instance}` | The child is in another instance or partition. |
| `{:error, :self_adoption}`, `{:error, :cyclic_parent}` | The adoption would create a cycle. |
| `{:error, :adoption_busy}` | Another adoption is running in this instance and partition. Retry. |
| `{:error, :invalid_child_options}` | The target is not a live server, or an option is invalid. |

## Related

- [Parent and Child Agents](../composition/parent-and-child-agents.md) compares the ways to compose Agents.
- [Runtime Effects](runtime-directives-and-effects.md) explains how the child Directives run after commit.
