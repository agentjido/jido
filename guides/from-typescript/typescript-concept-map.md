# TypeScript Concept Map

This guide is a lookup table from what you write in TypeScript and Node.js to its nearest form in Elixir and Jido. A row names the nearest match. Where the match is loose, the Differences column says how.

## Tools

| Node.js and TypeScript | Elixir | Differences |
| --- | --- | --- |
| `node` | `elixir`, or `iex` for an interactive shell | `iex -S mix` starts a shell with your project loaded |
| `npm`, `pnpm` | `mix`, with packages from Hex | `mix deps.get` installs dependencies |
| `package.json` | `mix.exs` | It is an Elixir file, and it holds dependencies and tasks |
| Lockfile | `mix.lock` | |
| `node_modules/` | `deps/` | Compiled output goes to `_build/` |
| `tsc` | `mix compile` | The compiler checks some type errors. See [Types and Validation](types-and-validation.md) |
| Prettier | `mix format` | Built in |
| A test runner such as Vitest | ExUnit, through `mix test` | Built in |
| `process.env` | `System.get_env/1`, or `config/runtime.exs` | |
| A container running one Node.js program | A release, built with `mix release` | One VM can hold the whole process tree |

## Language

| TypeScript | Elixir | Differences |
| --- | --- | --- |
| `const` and `let` | `=` | `=` matches a pattern and can rebind a name. Values never change |
| `{ id: "o-1" }` | `%{id: "o-1"}` | Atom keys, written `id:` |
| `{ "id": "o-1" }` from JSON | `%{"id" => "o-1"}` | String keys are a different key from atom keys |
| `"pending"` literal type | `:pending` atom | An atom is a named constant |
| `[a, b]` | `[a, b]` | A linked list. Read the head first |
| `[a, b]` as a fixed tuple | `{a, b}` | A tuple |
| `null`, `undefined` | `nil` | There is one empty value |
| `===` | `==` or `===` | Both compare by value, including maps and lists |
| `const { id } = order` | `%{id: id} = order` | A failed match raises `MatchError` |
| `switch` | `case`, or several function clauses | Clauses match on shape |
| `xs.map(f)`, `filter`, `reduce` | `Enum.map/2`, `Enum.filter/2`, `Enum.reduce/3` | |
| `f(g(x))` | `x \|> g() \|> f()` | The pipe passes the value as the first argument |
| Generator, async iterable | `Stream` | Lazy. It runs in the consuming process |
| `class` with fields and methods | `defmodule` with `defstruct` and functions | Functions take the struct as an argument and return a new one |
| `interface` that a class implements | `@behaviour` with `@callback` | Checked at compile time, with warnings |
| `import { f } from "./m"` | `alias M` then `M.f()`, or `import M` | Calls name a module, so no file path appears |
| `throw` | `raise`, or return `{:error, reason}` | See Errors and Async |
| Decorator, code generation | `use` and macros | Runs at compile time |

These rows show the first differences you will meet in code.

```typescript
const order = { id: "o-1", status: "open" };
const closed = { ...order, status: "closed" };

function label(status: "open" | "closed"): string {
  switch (status) {
    case "open":
      return "Open order";
    case "closed":
      return "Closed order";
  }
}
```

```elixir
defmodule ConceptMap.Orders do
  def label(%{status: :open}), do: "Open order"
  def label(%{status: :closed}), do: "Closed order"
end

order = %{id: "o-1", status: :open}
closed = %{order | status: :closed}

{"Open order", "Closed order"} = {ConceptMap.Orders.label(order), ConceptMap.Orders.label(closed)}
```

`%{order | status: :closed}` makes a new map, and `order` stays the same. It raises `KeyError` when the key is absent, which catches a misspelled field. Use `Map.put/3` to add a key.

JSON arrives with string keys, which is the most common surprise. `JSON` is part of the standard library from Elixir 1.18.

```elixir
decoded = JSON.decode!(~s({"id": "o-1"}))

"o-1" = decoded["id"]
nil = decoded[:id]
```

Do not convert untrusted keys with `String.to_atom/1`, because the VM never frees atoms. A schema can do this conversion for known keys. See [Types and Validation](types-and-validation.md).

## Runtime

| Node.js | BEAM | Differences |
| --- | --- | --- |
| Event loop | Schedulers running processes | See [Node.js and the BEAM](nodejs-and-the-beam.md) |
| `Promise` | `Task` | A task is a process |
| `await p` | `Task.await/2` | Exits the caller on timeout |
| `Promise.all` | `Task.await_many/2` | |
| `Promise.allSettled` | `Task.yield_many/2` | |
| `setTimeout` | `Process.send_after/3` | Delivers a message |
| `setInterval` | `:timer.send_interval/2`, or a `Jido.Plugin.Scheduler` schedule | |
| `AbortController` | `Process.exit/2`, `Task.shutdown/2` | The target needs no cooperation |
| `EventEmitter` | `send/2`, `Registry`, `Jido.Signal.Bus` | |
| Worker thread | Process | Start as many as the work calls for |
| `Map` used as a cache | ETS, or a process that holds state | ETS is a table in the VM that many processes can read |
| pm2, systemd restart | `Supervisor` | Works per process, inside the VM |
| Class instance holding state | `GenServer` | One message at a time |

Elixir has a standard module named `Agent` for holding state in a process. It is unrelated to `Jido.Agent`.

## Jido

| You would write in TypeScript | Jido term | Module | Differences |
| --- | --- | --- | --- |
| A function with a Zod schema on its input and output | Action | `Jido.Action` | Run through `Jido.Exec.run/4` for timeouts and retries |
| A workflow function with several `await` steps | Flow | `Jido.Flow` | A graph declared as data, so it can be inspected and stored |
| A Zod schema | Joi schema | `Jido.Joi` | See [Types and Validation](types-and-validation.md) |
| A CloudEvents object, a queue message | Signal | `Jido.Signal` | Has a `type`, a `source`, and `data` |
| A state type plus a reducer's `switch` | Agent | `Jido.Agent` | Routes map a Signal type to an Action or Flow |
| One call to `reducer(state, event)` | Turn | `Jido.Agent.cmd/3` | Returns next state and Directives |
| `{ type: "email", to }` returned from a reducer | Directive | `Jido.Agent.Directive` | See Effects as Data |
| A class instance with a request queue, under a process manager | AgentServer | `Jido.AgentServer` | Commits state, then performs Directives |
| A service container | Jido instance | `Jido` | A supervisor with a registry |
| A middleware or extension package | Plugin | `Jido.Plugin` | Adds its own state, routes, and Directive handling |
| Saved conversation history | Thread | `Jido.Thread` | See [Sessions and Threads](../data/sessions-and-threads.md) |

A Turn is the row to read twice. A Redux-style reducer takes state and an event and returns state. A Turn adds validation, routing, and a list of requested effects.

```typescript
type Event = { type: "invoice.payment.apply"; amountCents: number };
type State = { paidCents: number };

function reduce(state: State, event: Event): State {
  switch (event.type) {
    case "invoice.payment.apply":
      return { ...state, paidCents: state.paidCents + event.amountCents };
  }
}

const next = reduce({ paidCents: 0 }, { type: "invoice.payment.apply", amountCents: 1500 });
```

```elixir
defmodule ConceptMap.ApplyPayment do
  use Jido.Action,
    name: "concept_map_apply_payment",
    schema: Jido.Joi.object(%{amount_cents: Jido.Joi.integer() |> Jido.Joi.min(1)})

  @impl true
  def run(%{amount_cents: amount}, %{agent_state: state}) do
    {:ok, %{state | paid_cents: state.paid_cents + amount}}
  end
end

defmodule ConceptMap.Invoice do
  use Jido.Agent, name: "concept_map_invoice"

  state do
    schema Jido.Joi.object(%{paid_cents: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/billing/invoice"
    route "invoice.payment.apply", ConceptMap.ApplyPayment, as: :apply_payment
  end
end

invoice = ConceptMap.Invoice.instantiate!(id: "inv-1001")
payment = ConceptMap.Invoice.apply_payment_signal!(%{amount_cents: 1_500})

{:ok, next, []} = ConceptMap.Invoice.cmd(invoice, payment)

{0, 1_500} = {invoice.state.paid_cents, next.state.paid_cents}
```

The `as: :apply_payment` option generated `apply_payment_signal!/1`. Unlike a reducer, a Turn can fail: an invalid amount returns `{:error, reason}`, and no next state exists.

## Next steps

- [Jido Mental Model](../start-here/jido-mental-model.md) follows one Signal through these pieces.
- [Build Your First Action](../start-here/first-action.livemd) starts the hands-on path.
- Effects as Data explains the Directive row.
