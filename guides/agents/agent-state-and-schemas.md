# Agent State and Schemas

This guide shows how to declare Agent state, set its starting values, change it directly, and read the errors that protect it.

## Declare the schema

For Jido-owned state, the `state` section accepts a `schema` and an `initial_state`. The schema is a `Jido.Joi.object/2` value.

```elixir
defmodule StateGuide.TicketAgent do
  use Jido.Agent, name: "ticket"

  alias Jido.Joi

  state do
    schema Joi.object(%{
             subject: Joi.string(),
             status: Joi.enum([:open, :closed]) |> Joi.default(:open),
             assignee: Joi.string() |> Joi.nullable() |> Joi.default(nil),
             routing: Joi.map() |> Joi.default(%{queue: "general", priority: 3})
           })

    initial_state %{status: :open, routing: %{queue: "support", priority: 2}}
  end
end

ticket = StateGuide.TicketAgent.instantiate!(id: "t-1", state: %{subject: "Refund request"})

%{subject: "Refund request", status: :open, assignee: nil, routing: %{queue: "support", priority: 2}} =
  ticket.state
```

A state schema must be static stored data, because Jido validates and can save it with the definition. `Jido.Agent.define/1` rejects:

- a schema that is not an object, such as `Jido.Joi.string()`;
- a coercing field, such as `Jido.Joi.integer(coerce: true)`;
- a transform, such as `Jido.Joi.transform/2` with a function.

```elixir
for schema <- [
      Jido.Joi.string(),
      Jido.Joi.object(%{age: Jido.Joi.integer(coerce: true)}),
      Jido.Joi.object(%{subject: Jido.Joi.string() |> Jido.Joi.transform(&String.trim/1)})
    ] do
  {:error, %Jido.Error.ValidationError{path: [:schema | _]}} =
    Jido.Agent.define(%{name: "ticket", schema: schema})
end
```

## How the starting state is built

`Jido.Agent.instantiate/2` builds new state in this order:

1. It merges explicit `:state` over `initial_state`. The merge is shallow.
2. It passes that candidate to the module's optional [`initialize/2` callback](agent-callbacks.md).
3. It applies the schema, which adds defaults and validates the complete state.

So an explicit value beats `initial_state`, and `initial_state` beats a schema default. An explicit `nil` also takes a field's default.

```elixir
explicit =
  StateGuide.TicketAgent.instantiate!(
    id: "t-2",
    state: %{subject: "Late delivery", routing: %{queue: "shipping", priority: 1}, assignee: nil}
  )

%{queue: "shipping", priority: 1} = explicit.state.routing
nil = explicit.state.assignee

# A schema default fills a nil field.
defaulted = StateGuide.TicketAgent.instantiate!(id: "t-3", state: %{subject: "Login", status: nil})
:open = defaulted.state.status
```

`initial_state` must be a plain, static Map. It cannot hold a PID or a function.

The final state is closed. A key the schema does not declare is rejected, even when the schema is an open object:

```elixir
{:error, %Jido.Error.ValidationError{code: :invalid_state, path: [:state]}} =
  StateGuide.TicketAgent.instantiate(id: "t-4", state: %{subject: "Login", tag: "vip"})
```

Instantiation adds defaults but does not convert values. A string in an integer field is an error.

## Change state directly

`Jido.Agent.set/2` replaces the top-level domain fields you supply and validates the complete result. It takes a Map or a keyword list and returns a new value.

```elixir
{:ok, assigned} = Jido.Agent.set(ticket, assignee: "dana")

{"dana", nil} = {assigned.state.assignee, ticket.state.assignee}
```

A nested Map replaces the old Map. To keep its other keys, merge before you call `set/2`:

```elixir
routing = Map.merge(ticket.state.routing, %{priority: 1})
{:ok, escalated} = Jido.Agent.set(ticket, routing: routing)

%{queue: "support", priority: 1} = escalated.state.routing
```

An undeclared key returns an error that names it:

```elixir
{:error, %Jido.Error.ValidationError{details: %{keys: [:tag]}}} =
  Jido.Agent.set(ticket, tag: "vip")
```

Use `set/2` for setup and tests. Use a route when the change is a command to the Agent, because a route has a Signal, runs Plugin steps, and can return Directives. A live Agent changes state only through a Signal.

## Validate a stored value

`Jido.Agent.validate/1` checks a definition or an instance. It does not insert defaults, so stored state must already be complete.

```elixir
{:ok, _ticket} = Jido.Agent.validate(ticket)

{:error, %Jido.Error.ValidationError{code: :incomplete_state}} =
  Jido.Agent.validate(%{ticket | state: %{subject: "Refund request"}})
```

`Jido.Agent.definition?/1` and `Jido.Agent.instance?/1` check shape only.

## Use an Ecto row as Agent state

Add `:ecto_sql` and an Ecto adapter to your application. Start the Repo
before you run a live Turn. The schema must export `repo/0` and
`changeset/2`. Give the row one primary key and a non-null integer
`lock_version`. Create the row before the first Turn. Its primary key must
match the Agent ID.

```elixir
defmodule MyApp.CounterState do
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "counter_state" do
    field :count, :integer
    field :lock_version, :integer, default: 1
  end

  def repo, do: MyApp.Repo

  def changeset(row, attrs), do: Ecto.Changeset.cast(row, attrs, [:count])
end

defmodule MyApp.CounterAgent do
  use Jido.Agent, name: "counter"
  alias Jido.Plugin.EctoState

  state do
    ecto MyApp.CounterState
  end

  routes do
    signal_source "/my_app/counter"

    route "counter.increment" do
      action _input, context: context do
        row = context.plugin_inputs[EctoState].runtime.row
        changes = %{count: row.count + 1}
        {:ok, changes, [EctoState.update(changes)]}
      end

      state :unchanged
      reply "counter.incremented", from: output()
    end
  end
end
```

Use only `ecto SchemaModule` in this state block. The compiler rejects
`schema`, `initial_state`, and options on the `ecto` declaration.

Each live Turn reads the current row. The Action reads the row from its
Plugin input and can return one update Directive. Any reply comes from the
route's own output. The Plugin uses the schema's changeset and checks
`lock_version` when it saves. A stale row fails the Turn before the caller
receives success. A Turn with no update Directive only reads the row.

Run the Agent with Jido persistence disabled to write to the Ecto row.
When Jido persistence is enabled, the Plugin rejects update proposals and
permits read-only Turns. A durable Flow saves its admitted row in the
continuation checkpoint and uses that input when it resumes. If another
writer changes the SQL row, it must also advance `lock_version`.

The usual live snapshot reads the current row without starting a Turn.

```elixir
%{agent: %{state: %{count: count}}} = Jido.AgentServer.snapshot(server)
```

The read includes persisted schema fields. If a field has the same key as a
Jido-owned field, the Jido-owned value takes precedence. The Jido revisions
track Jido commits, and the row's `lock_version` tracks external changes.

The query uses the Agent ID as the primary key in the schema's Repo. Give
Agents different IDs to keep separate rows in the same table and prefix, even
when the Agents use different Jido namespaces or partitions.

## Plugin-owned fields

A Plugin can own one state field. Domain fields and Plugin fields share one Map, and the Agent's complete schema includes both. Read it with `Jido.Agent.schema/1` or the module's generated `schema/0`.

```elixir
defmodule StateGuide.AuditTrail do
  use Jido.Plugin

  @impl true
  def state_spec(_opts), do: {:audit_events, Jido.Joi.integer() |> Jido.Joi.default(0)}

  @impl true
  def reduce(reduction, _opts), do: {:ok, reduction.plugin_state + 1}
end

defmodule StateGuide.AuditedAgent do
  use Jido.Agent, name: "audited_ticket", plugins: [StateGuide.AuditTrail]

  state do
    schema Jido.Joi.object(%{status: Jido.Joi.string() |> Jido.Joi.default("open")})
  end

  routes do
    route "ticket.close" do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        {:ok, %{context.agent_state | status: "closed"}}
      end
    end

    route "ticket.tamper" do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        {:ok, %{context.agent_state | audit_events: 99}}
      end
    end
  end
end

audited = StateGuide.AuditedAgent.instantiate!(id: "t-5")
%{status: "open", audit_events: 0} = audited.state

close = Jido.Signal.new!("ticket.close", %{}, source: "/tickets")
{:ok, closed, []} = StateGuide.AuditedAgent.cmd(audited, close)
%{status: "closed", audit_events: 1} = closed.state
```

An Action must return Plugin-owned fields unchanged. `Jido.Agent.set/2` rejects them too.

```elixir
tamper = Jido.Signal.new!("ticket.tamper", %{}, source: "/tickets")
{:error, %{details: %{code: :plugin_state_owner_violation}}} = StateGuide.AuditedAgent.cmd(audited, tamper)

{:error, %Jido.Error.ValidationError{details: %{keys: [:audit_events]}}} =
  Jido.Agent.set(audited, audit_events: 5)
```

## State errors

State and schema failures are `Jido.Error.ValidationError` values. State checks use a `path` that starts at `[:state]`. Definition checks use the field they reject, such as `[:schema]` or `[:initial_state]`.

| `code` | Meaning |
| --- | --- |
| `:invalid_state` | A value does not match the schema, or a key is not declared. `details.issues` lists each field. |
| `:incomplete_state` | Stored or candidate state is missing a required field. |
| `:state_conversion` | Applying the schema would change a supplied value. |
| `:invalid_schema` | The schema is not a static object suited to stored state. |
| `:live_value` | A schema, `initial_state`, or `metadata` contains a live value such as a PID or a function. |

## Related

- [Jido.Joi Validation](../data/joi-validation.md) covers schema functions.
- State and Directives covers how a Turn returns state.
- [Agent Callbacks](agent-callbacks.md) covers `initialize/2`.
