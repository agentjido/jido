# Change Live Composition

You have a running team and need to add a member, resize a group, or rewire
a connection without stopping the parent. In Jido, you return the change from
a Turn on the parent. The Server commits it, then changes the process tree to
match:

```elixir
route "crew.reviewer.add", as: :add_reviewer do
  action _input, name: "add_reviewer", schema: Zoi.object(%{}), context: context do
    {:ok, context.agent_state,
     [D.agent_add(:reviewer, Crew.Worker, initial_state: %{role: "reviewer"})]}
  end
end
```

This guide shows the Directives that change composition, how the Server
reconciles processes after commit, which processes survive, and what Jido
rejects. Read [Nested Agents](declare-agent-topology.livemd) and
[Connect Agent Outputs](connect-agent-outputs.livemd) first.

## What Survives

You change a live team in one of two ways:

1. **Change bound state.** If a member's `count` or `initial_state` uses
   `state/1`, an ordinary state change resizes or rebinds it.
2. **Return a mutation Directive.** Add, update, replace, or remove members
   and connections.

After commit, a slot whose definition and bound state didn't change keeps its
process.

| Change | Effect on processes |
| --- | --- |
| Count grows | Existing slots stay. New slots start. |
| Count shrinks | The lowest slots stay. The highest slots stop. |
| Bound `initial_state` value changes | Every slot of that member is replaced. |
| Member definition changes | Every slot of that member is replaced. |
| Member removed | Every slot of that member stops, with its children. |
| Connection added, updated, or removed | No process changes. |
| Unrelated parent state changes | No process changes. |

## Mutation Directives

All constructors are in `Jido.Agent.Directive`:

| Directive | Effect on the candidate topology |
| --- | --- |
| `agent_add(name, definition, opts)` | Adds a member. Options: `count:`, `initial_state:`. |
| `agent_update(name, changes)` | Merges `changes` into a member. Keys: `:definition`, `:count`, `:initial_state`. |
| `agent_replace(name, definition, opts)` | Replaces a member declaration. |
| `agent_remove(name)` | Removes a member. |
| `connection_add(path, from:, to:, delivery:)` | Adds a connection. |
| `connection_update(path, from:, to:, changes:)` | Merges `changes` into a connection. Key: `:delivery`. |
| `connection_replace(path, from:, to:, delivery:)` | Replaces a connection. |
| `connection_remove(path, from:, to:)` | Removes a connection. |
| `topology_set(topology)` | Replaces the whole topology. |

A mutation Directive edits the candidate Agent before commit. It doesn't
start or stop anything itself. The Server changes processes only after the
commit succeeds.

## The Example Crew

The examples use a crew whose worker count is bound to `size`, with routes
that return mutation Directives:

```elixir
defmodule Crew.Worker do
  use Jido.Agent, name: "crew_worker"

  state do
    schema(
      Zoi.object(%{
        role: Zoi.string() |> Zoi.default("worker"),
        done: Zoi.integer() |> Zoi.default(0)
      })
    )
  end

  routes do
    signal_source("/guides/change")

    route "task.run", as: :run do
      action _input, name: "run", schema: Zoi.object(%{}), context: context do
        {:ok, %{context.agent_state | done: context.agent_state.done + 1}}
      end
    end
  end
end

defmodule Crew.Lead do
  use Jido.Agent, name: "crew"
  alias Jido.Agent.Directive, as: D

  state do
    schema(Zoi.object(%{size: Zoi.integer() |> Zoi.default(2)}))
  end

  routes do
    signal_source("/guides/change")

    route "crew.resize", as: :resize do
      action %{size: size}, name: "resize", schema: Zoi.object(%{size: Zoi.integer()}),
        context: context do
        {:ok, %{context.agent_state | size: size}}
      end
    end

    route "crew.reviewer.add", as: :add_reviewer do
      action _input, name: "add_reviewer", schema: Zoi.object(%{}), context: context do
        {:ok, context.agent_state,
         [D.agent_add(:reviewer, Crew.Worker, initial_state: %{role: "reviewer"})]}
      end
    end

    route "crew.reviewer.replace", as: :replace_reviewer do
      action _input, name: "replace_reviewer", schema: Zoi.object(%{}), context: context do
        {:ok, context.agent_state,
         [D.agent_replace(:reviewer, Crew.Worker, initial_state: %{role: "senior"})]}
      end
    end

    route "crew.reviewer.remove", as: :remove_reviewer do
      action _input, name: "remove_reviewer", schema: Zoi.object(%{}), context: context do
        {:ok, context.agent_state, [D.agent_remove(:reviewer)]}
      end
    end

    route "crew.workers.pin", as: :pin do
      action %{count: count}, name: "pin", schema: Zoi.object(%{count: Zoi.integer()}),
        context: context do
        {:ok, context.agent_state, [D.agent_update(:workers, %{count: count})]}
      end
    end
  end

  topology do
    agent :workers, Crew.Worker do
      count state(:size)
    end
  end
end
```

## Test A Change Purely

`cmd/2` applies mutation Directives to the candidate, so you can test a
composition change without a process:

```elixir
crew = Crew.Lead.instantiate!(id: "crew-1")
add = Crew.Lead.add_reviewer_signal!()
{:ok, candidate, [_directive]} = Crew.Lead.cmd(crew, add)

Enum.map(candidate.topology.agents, & &1.name)
# => [:workers, :reviewer]

diff = Jido.Agent.Diff.between(crew, candidate)
{Jido.Agent.Diff.changed?(diff, :agents), Jido.Agent.Diff.changed?(diff, :state)}
# => {true, false}
```

`Jido.Agent.mutate/2` applies a list of mutations without a route. See
[Mutations and Diffs](agent-mutations-and-diffs.livemd).

## Resize Through State

Start the crew, give each worker one task, then grow `size` from 2 to 3:

```elixir
alias Jido.AgentServer, as: Server

{:ok, _jido} = Jido.start()
{:ok, server} = Jido.start_agent(Crew.Lead, id: "crew-1")
:ok = Server.await_ready(server)

original = Server.members(server, :workers)
run = Crew.Worker.run_signal!()
Enum.each(original, fn worker -> {:ok, _, []} = Server.call(worker, run) end)

grow = Crew.Lead.resize_signal!(%{size: 3})
{:ok, _crew, []} = Server.call(server, grow)
:ok = Server.await_ready(server)

grown = Server.members(server, :workers)
{Enum.take(grown, 2) == original, Enum.map(grown, &Server.agent(&1).state.done)}
# => {true, [1, 1, 0]}
```

Slots 1 and 2 kept their processes and their state. Slot 3 is new. The Turn
returned no Directives: the state change alone resized the team.

Shrink to 1:

```elixir
shrink = Crew.Lead.resize_signal!(%{size: 1})
{:ok, _crew, []} = Server.call(server, shrink)
:ok = Server.await_ready(server)

Server.members(server, :workers) == [hd(original)]
# => true
```

Slots 2 and 3 stopped. Slot 1 kept running.

## Add, Replace, Remove

```elixir
{:ok, _crew, [_add]} = Server.call(server, add)
:ok = Server.await_ready(server)
[reviewer] = Server.members(server, :reviewer)

replace = Crew.Lead.replace_reviewer_signal!()
{:ok, _crew, [_replace]} = Server.call(server, replace)
:ok = Server.await_ready(server)
[senior] = Server.members(server, :reviewer)

{senior != reviewer, Process.alive?(reviewer), Server.agent(senior).state.role}
# => {true, false, "senior"}
```

`agent_replace/3` stopped the old reviewer and started a new process with the
new initial state. The worker didn't change.

`agent_remove/1` stops every slot of the member and everything those slots
own:

```elixir
remove = Crew.Lead.remove_reviewer_signal!()
{:ok, _crew, [_remove]} = Server.call(server, remove)
:ok = Server.await_ready(server)

{Server.members(server, :reviewer), Process.alive?(senior)}
# => {[], false}
```

## Pin A Bound Count

`agent_update/2` with a literal `count` replaces the `state(:size)` binding.
After that, `size` no longer controls the team:

```elixir
pin = Crew.Lead.pin_signal!(%{count: 2})
{:ok, pinned, [_update]} = Server.call(server, pin)
:ok = Server.await_ready(server)

resize = Crew.Lead.resize_signal!(%{size: 4})
{:ok, _crew, []} = Server.call(server, resize)
:ok = Server.await_ready(server)

{hd(pinned.topology.agents).count, length(Server.members(server, :workers))}
# => {2, 2}
```

Use a binding when the team should follow state. Use a literal when only an
explicit Directive should change it.

## Rewire In One Turn

Connection Directives change routing and never restart a member. One Action
can remove a connection, add another, and emit through the new wiring:

```elixir
alias Jido.Agent.Directive, as: D

{:ok, state,
 [
   D.connection_remove("job.posted", from: :root, to: :left),
   D.connection_add("job.posted", from: :root, to: :right),
   emit("job.posted", %{id: 7})
 ]}
```

Jido applies the mutations to the candidate before commit. The `Emit` runs
after commit, against the new connections, so the Signal reaches `:right`.

## Rejected Changes

Jido validates a composition change with the rest of the candidate. A
rejected change leaves the state, the revision, and every process unchanged:

```elixir
before = Server.snapshot(server)
children = Server.children(server)

zero = Crew.Lead.pin_signal!(%{count: 0})
{:error, error} = Server.call(server, zero)
Exception.message(error)
# => "Expected a positive integer"

{Server.snapshot(server) == before, Server.children(server) == children}
# => {true, true}
```

Jido also rejects:

- a count, literal or bound, that isn't a positive integer;
- `agent_add` for an existing name, or `agent_update` for a missing one
  (`"Agent mutation failed"`);
- a connection whose destination has no route for its type
  (`:unaccepted_type`);
- `:single` delivery to a counted member (`:counted_delivery`);
- a member definition that contains itself.

## How Reconcile Works

After a commit that changes members, connections, buses, or bound state, the
Server:

1. binds every member against the committed state;
2. keeps each slot whose definition and bound state are unchanged;
3. stops changed and removed slots, and confirms they exited;
4. starts missing slots and waits until each is ready;
5. starts or stops declared topology buses.

The commit reply can arrive before step 5 finishes. Call
`Jido.AgentServer.await_ready/2` before you read members. Reads work during
reconciliation. New Turns wait for it to finish.

## Rules And Limits

- **An activation is required.** A bare worker started with
  `Jido.AgentServer.start_link/1` rejects topology changes with
  `:activation_required`. `Jido.start_agent/2` creates an activation.
- **Use mutations for topology members.** `agent_stop/2` on a topology member
  returns `:topology_agent_requires_mutation`. Use `agent_remove/1` or change
  the binding.
- **Members restart permanently.** A crashed slot restarts under the parent's
  activation from its own last commit.
- **Slot identity belongs to the slot.** With persistence, each slot saves an
  identity with the parent's topology. Remove a member and its identity goes.
  Add it again and it starts with fresh state.
- **Reconciliation is local.** It doesn't move members between nodes or save
  the team as one snapshot. Each persistent member restores its own last
  commit. The Advanced guides "Durable Activation" and "Checkpoints and
  Upgrades" cover persistence.

## Stop The Example

```elixir
:ok = Jido.stop_agent("crew-1")
:ok = Jido.stop()
```

## Next

- [Composition Vocabulary](composition-vocabulary.md) for the terms.
- [Plugin Persistence](plugin-persistence-and-live-changes.md) for adding and
  changing Plugins on a live Agent.
