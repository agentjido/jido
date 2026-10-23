# Types and Validation

This guide maps TypeScript types and Zod schemas to Elixir, Zoi, and Jido. It
covers where each check runs, why Agent state schemas never convert values,
how routes replace a discriminated-union `switch`, what fails `mix compile`,
and how JSON keys reach your Actions.

> #### Learn Elixir first {: .tip}
>
> This guide assumes you can read basic Elixir. The official guides cover it:
> [Introduction](https://hexdocs.pm/elixir/introduction.html),
> [Pattern matching](https://hexdocs.pm/elixir/pattern-matching.html),
> [Processes](https://hexdocs.pm/elixir/processes.html), and
> [Keyword lists and maps](https://hexdocs.pm/elixir/keywords-and-maps.html).

The examples run in a Mix project that depends on `{:jido, "~> 3.0.0-beta.2"}`.
Zoi ships with Jido.

## Static vs Runtime

In TypeScript, the compiler checks your types and then erases them. At runtime
a request body is `unknown` until a Zod schema parses it. You need both
layers: types for your code, Zod for the data that crosses the boundary.

Elixir has no type layer to erase. Every value carries its type at runtime,
and Zoi does the job Zod does: it parses data and returns `{:ok, value}` or
`{:error, [%Zoi.Error{}]}`. Jido runs a Zoi schema at every boundary it owns:
Agent state, Action input, and typed Signal data.

Two build-time tools check code, not data:

- The compiler infers types from patterns and guards and warns when a call can
  never succeed. You can't write type annotations for it yet. See
  [Gradual set-theoretic types](https://hexdocs.pm/elixir/gradual-set-theoretic-types.html).
- Dialyzer reads `@spec` annotations and reports contradictions. It is a
  separate, slower analysis that you run on demand.

Neither tool sees a Zoi schema, and neither checks the JSON a client sends.

## Zod to Zoi

A Zod object schema:

```typescript
const Profile = z.object({
  name: z.string().min(1).default("Anonymous"),
  age: z.number().int().min(0).optional(),
  role: z.enum(["admin", "member"]).default("member"),
  tags: z.array(z.string()).default([]),
});

type Profile = z.infer<typeof Profile>;
const profile = Profile.parse({ name: "Ada" });
```

The same shape as a Jido Agent state schema:

```elixir
defmodule Types.Profile do
  use Jido.Agent, name: "profile"

  state do
    schema(
      Zoi.object(%{
        name: Zoi.string() |> Zoi.min(1) |> Zoi.default("Anonymous"),
        age: Zoi.integer() |> Zoi.min(0) |> Zoi.optional(),
        role: Zoi.enum([:admin, :member]) |> Zoi.default(:member),
        tags: Zoi.list(Zoi.string()) |> Zoi.default([])
      })
    )
  end
end

profile = Types.Profile.instantiate!(id: "profile-1", state: %{name: "Ada"})
profile.state
```

The result is `%{name: "Ada", role: :member, tags: []}`. The optional `age`
is absent, not `nil`.

The analogy breaks in three places:

- There is no `z.infer`. A Zoi schema is a runtime value. The compiler derives
  no type from it.
- Zod and plain `Zoi.parse/2` strip unknown keys. Jido state validation
  rejects them.
- Jido wraps Zoi issues in one `Jido.Agent.Error`:

```elixir
{:error, error} =
  Types.Profile.instantiate(id: "profile-2", state: %{name: "", nickname: "A"})

{error.code, Enum.map(error.details.issues, &{&1.path, &1.message})}
```

The result is:

```text
{:invalid_state,
 [{[:name], "too small: must have at least 1 character(s)"},
  {[], "unrecognized key: nickname"}]}
```

`Exception.message(error)` is `"State does not match its schema"`. Read
`details.issues` for the field paths.

| Zod | Zoi |
| --- | --- |
| `z.object({...})` | `Zoi.object(%{...})` |
| `z.string()`, `z.number().int()` | `Zoi.string()`, `Zoi.integer()` |
| `.min(n)`, `.default(v)`, `.optional()` | `Zoi.min/2`, `Zoi.default/2`, `Zoi.optional/1` |
| `z.enum([...])`, `z.literal(v)` | `Zoi.enum/1`, `Zoi.literal/1` |
| `z.array(t)`, `z.record(k, v)` | `Zoi.list/1`, `Zoi.map/2` |
| `z.discriminatedUnion(k, [...])` | `Zoi.discriminated_union/2` |
| `.refine(fn)`, `.transform(fn)` | `Zoi.refine/2`, `Zoi.transform/2` |
| `z.coerce.number()` | `Zoi.integer(coerce: true)` |
| `.safeParse(v)`, `.parse(v)` | `Zoi.parse/2`, `Zoi.parse!/2` |

The [Zoi documentation](https://hexdocs.pm/zoi) covers the full API.

## Validate, Never Convert

Agent state schemas validate values. They never convert them. This is the
largest change for a Zod user.

In Zod, a parse can change the value:

```typescript
const Person = z.object({ age: z.coerce.number().int().min(0) });
Person.parse({ age: "36" }); // { age: 36 }
```

In Jido, put the conversion in the Action input schema. The state schema then
checks a value that is already correct:

```elixir
defmodule Types.SetAge do
  use Jido.Action,
    name: "set_age",
    schema: Zoi.object(%{age: Zoi.integer(coerce: true) |> Zoi.min(0)})

  @impl true
  def run(%{age: age}, %{agent_state: state}), do: {:ok, Map.put(state, :age, age)}
end

defmodule Types.Person do
  use Jido.Agent, name: "person"

  state do
    schema(Zoi.object(%{age: Zoi.integer() |> Zoi.min(0) |> Zoi.optional()}))
  end

  routes do
    signal_source("/guides/types")
    route "person.age.set", Types.SetAge, as: :set_age
  end
end

person = Types.Person.instantiate!(id: "person-1")
signal = Types.Person.set_age_signal!(%{age: "36"})
{:ok, updated, []} = Types.Person.cmd(person, signal)

updated.state
```

The result is `%{age: 36}`. The Action input schema converted `"36"`. The
state schema saw an integer.

The analogy breaks because Jido splits one Zod schema into two jobs. The
Action input schema can coerce and transform. The state schema can only
accept or reject.

Give the state the string directly and it fails:

```elixir
{:error, error} = Types.Profile.instantiate(id: "profile-3", state: %{age: "36"})

Enum.map(error.details.issues, &{&1.path, &1.message})
```

The result is `[{[:age], "invalid type: expected integer"}]`. An Action that
returns `age: "36"` fails its Turn with the same `:invalid_state` error, and
the Agent keeps its committed state.

A state schema that could convert fails the build. These all fail:

- `coerce: true` on a field or on the object;
- `Zoi.transform/2` anywhere in the schema;
- codec and lazy schemas.

Defaults and checks such as `Zoi.min/2` and `Zoi.enum/1` are allowed.
A `Zoi.refine/2` in a module attribute or DSL needs an MFA tuple, such as
`Zoi.refine({MyApp.Rules, :not_blank, []})`. An anonymous function fails to
compile with `cannot escape #Function<...>`. In `Jido.Agent.define/1` it
fails with `"Authoring data cannot contain live values"`.

## Unions and Matching

A TypeScript reducer narrows a discriminated union with `switch`:

```typescript
type Event =
  | { type: "counter.increment"; amount: number }
  | { type: "counter.reset" };

function reduce(state: { count: number }, event: Event) {
  switch (event.type) {
    case "counter.increment":
      return { ...state, count: state.count + event.amount };
    case "counter.reset":
      return { ...state, count: 0 };
  }
}
```

In Jido, the Signal `type` is the discriminator and each route is one case.
Each route has its own input schema:

```elixir
defmodule Types.Counter do
  use Jido.Agent, name: "counter"

  state do
    schema(Zoi.object(%{count: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0)}))
  end

  routes do
    signal_source("/guides/types")

    route "counter.increment", as: :increment do
      action %{amount: amount},
        schema: Zoi.object(%{amount: Zoi.integer() |> Zoi.min(1)}), context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + amount}}
      end
    end

    route "counter.reset", as: :reset do
      action _input, schema: Zoi.object(%{}), context: context do
        {:ok, %{context.agent_state | count: 0}}
      end
    end
  end
end

counter = Types.Counter.instantiate!(id: "counter-1")
{:ok, counter, []} = Types.Counter.cmd(counter, Types.Counter.increment_signal!(%{amount: 4}))

counter.state
```

The result is `%{count: 4}`. `reset_signal!/0` then gives `%{count: 0}`.

The analogy breaks at exhaustiveness. TypeScript can prove at compile time
that a `switch` handles every member. Jido can't know which Signal types will
arrive, so an unhandled type fails its Turn at runtime:

```elixir
signal = Jido.Signal.new!("counter.decrement", %{}, source: "/guides/types")
{:error, error} = Types.Counter.cmd(counter, signal)

{error.code, Exception.message(error)}
```

The result is `{:unmatched_input, "No route accepts this Signal type"}`. A
payload that fails the route schema, such as `amount: 0`, fails with
`Jido.Action.Error.InvalidInputError`: `"too small: must be at least 1, at amount"`.

For a union stored in state, use `Zoi.discriminated_union/2` and match on it
with function clauses:

```elixir
defmodule Types.Job do
  use Jido.Agent, name: "job"

  state do
    schema(
      Zoi.object(%{
        status:
          Zoi.discriminated_union(:kind, [
            Zoi.object(%{kind: Zoi.literal(:idle)}),
            Zoi.object(%{kind: Zoi.literal(:running), started_at: Zoi.integer()}),
            Zoi.object(%{kind: Zoi.literal(:failed), reason: Zoi.string()})
          ])
          |> Zoi.default(%{kind: :idle})
      })
    )
  end

  def label(%{status: %{kind: :idle}}), do: "idle"
  def label(%{status: %{kind: :running, started_at: at}}), do: "running since #{at}"
  def label(%{status: %{kind: :failed, reason: reason}}), do: "failed: #{reason}"
end

job = Types.Job.instantiate!(id: "job-1", state: %{status: %{kind: :failed, reason: "timeout"}})
Types.Job.label(job.state)
```

The result is `"failed: timeout"`. `%{kind: :done}` fails instantiation with
`"unknown discriminator 'done' for field 'kind'"`. Clauses that match no value
raise `FunctionClauseError` at runtime. The compiler doesn't check that the
clauses cover the union.

## Checked at Compile Time

Jido checks the Agent definition when the module compiles. These mistakes fail
`mix compile`:

```elixir
defmodule MyApp.Counter do
  use Jido.Agent, name: "counter"

  routes do
    route "counter.increment", MyApp.Increment
  end
end

defmodule MyApp.Increment do
  def run(_params, _context), do: :ok
end
```

`MyApp.Increment` is not an Action, so the build stops with:

```text
** (Jido.Agent.Error) Expected an Action or Flow module
```

The message names no file or line. Look for the route whose target module
lacks `use Jido.Action` or `use Jido.Flow`, or has a misspelled name.

A state schema that converts values fails with the file and module:

```text
== Compilation error in file lib/counter.ex ==
** (Spark.Error.DslError) [MyApp.Counter]
schema -> 3 -> 0 -> 1 :
  State schemas cannot convert values
    lib/counter.ex:1: MyApp.Counter (module)
```

Two routes with the same path fail with `"Duplicate declaration"`.
[Routes and Handlers](build-agent-routes.livemd) lists the other route rules.

Some mistakes compile and fail at runtime:

| Mistake | When it fails |
| --- | --- |
| `Zoi.default("zero")` on `Zoi.integer()` | `instantiate/1`, with `"invalid type: expected integer"` |
| Signal data that breaks the Action schema | The Turn, with `InvalidInputError` |
| A Signal type with no route | The Turn, with `:unmatched_input` |

Generated helpers such as `increment_signal!/2` check only that the data is a
map. They don't run the Action schema. `Types.Counter.increment_signal!(%{amount: 0})`
returns a Signal, and its Turn fails. Validate untrusted input before Signal
construction when the caller needs an earlier failure.

## Data at the Boundary

JSON object keys are strings. Jido keeps them as strings until a schema
converts them:

```elixir
json =
  ~s({"specversion":"1.0","id":"req-1","type":"cart.item.add",) <>
    ~s("source":"/web","data":{"sku":"tea","quantity":"2"}})

{:ok, signal} = Jido.Signal.Serialization.deserialize(json)
signal.data
```

The result is `%{"quantity" => "2", "sku" => "tea"}`. Agent state and Action
input use atom keys, so an Action with `Zoi.object(%{sku: Zoi.string()})`
rejects this data with `"is required, at sku"`.

In TypeScript, you parse once and get typed data:

```typescript
const AddItem = z.object({
  sku: z.string(),
  quantity: z.coerce.number().int().min(1).default(1),
});
const input = AddItem.parse(JSON.parse(body).data);
```

In Jido, the Action input schema validates request data during the Turn.
`coerce: true` on the object converts known string keys to atoms, and
`coerce: true` on a field converts its value:

```elixir
defmodule Types.AddItem do
  use Jido.Action,
    name: "add_item",
    description: "Adds one item to the cart",
      schema:
        Zoi.object(
          %{
            sku: Zoi.string(),
            quantity: Zoi.integer(coerce: true) |> Zoi.min(1) |> Zoi.default(1)
          },
          coerce: true
        )

  @impl true
  def run(%{sku: sku, quantity: quantity}, %{agent_state: state}) do
    {:ok, %{state | items: Map.update(state.items, sku, quantity, &(&1 + quantity))}}
  end
end

defmodule Types.Cart do
  use Jido.Agent, name: "cart"

  state do
    schema(Zoi.object(%{items: Zoi.map(Zoi.string(), Zoi.integer()) |> Zoi.default(%{})}))
  end

  routes do
    signal_source("/guides/types")

    route "cart.item.add", Types.AddItem, as: :add_item
  end
end

cart = Types.Cart.instantiate!(id: "cart-1")
{:ok, cart, []} = Types.Cart.cmd(cart, signal)

cart.state
```

The result is `%{items: %{"tea" => 2}}`. The Action receives
`%{quantity: 2, sku: "tea"}` after input validation and coercion.

The analogy breaks at keys. `JSON.parse` gives you property names that match
your types. Elixir atoms and strings are different keys, and only a schema
with `coerce: true` maps one to the other. Don't call `String.to_atom/1` on
client keys: the VM never frees atoms, and the atom table has a fixed limit.

| Layer | Converts keys or values |
| --- | --- |
| `Jido.Signal.new/3`, `deserialize/2` | No. Data stays as given. |
| Route helpers, such as `add_item_signal!/2` | No. They check only for a map. |
| Action input schema, during the Turn | Only where the schema sets `coerce: true` or `Zoi.transform/2`. |
| Agent state schema | Never. |

Keep fixed fields as atom keys and data-driven keys as strings, like the
`items` map above: `Zoi.map(Zoi.string(), Zoi.integer())` is the
`z.record(z.string(), z.number())` of Zoi.

The rule also applies outbound. JSON serialization accepts only string keys:

```elixir
Jido.Signal.new!("cart.item.added", %{sku: "tea"}, source: "/guides/types")
|> Jido.Signal.Serialization.serialize()
```

The result is
`{:error, {:json_encode_failed, "Signal data must contain JSON values or binary data"}}`.
Use `%{"sku" => "tea"}` for Signal data that leaves the VM as JSON.

## Next

- [Errors and Async](errors-and-async.md) covers error values and
  asynchronous work.
- [Routes and Handlers](build-agent-routes.livemd) covers Action input and
  route-generated replies.
