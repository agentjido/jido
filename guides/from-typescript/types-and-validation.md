# Types and Validation

This guide shows how to move TypeScript types and Zod schemas to Elixir and `Jido.Joi`. You learn which tool checks what, how to validate JSON at a boundary, and how to publish a contract to TypeScript clients.

## What checks what, and when

TypeScript checks your program before it runs, then erases the types. Zod or a similar library checks untrusted data at runtime. Elixir has the same split with different tools.

| Check | TypeScript | Elixir | When |
| --- | --- | --- | --- |
| Program structure | `tsc` | The compiler reports some type errors as warnings, without annotations | Build |
| Declared signatures | Type annotations, enforced by `tsc` | `@spec`, read by Dialyzer and documentation tools. The compiler does not enforce it | Build, when you run Dialyzer |
| Data shape in code | Type narrowing | Pattern matching and guards | Runtime |
| Untrusted data | Zod | `Jido.Joi` | Runtime |

Elixir is dynamically typed, so a `@spec` does not reject a bad call at runtime. Many shape checks that TypeScript does at build time happen at runtime in Elixir, through patterns close to the value and schemas at each boundary.

## Move a type to a struct

An `interface` or object type usually becomes a struct with a `@type`. A struct has a fixed set of keys. `@enforce_keys` requires keys at construction.

```typescript
interface Invoice {
  id: string;
  totalCents: number;
  paidCents?: number;
}

const invoice: Invoice = { id: "inv-1001", totalCents: 5000 };
```

```elixir
defmodule TypesGuide.Invoice do
  @enforce_keys [:id, :total_cents]
  defstruct [:id, :total_cents, paid_cents: 0]

  @type t :: %__MODULE__{
          id: String.t(),
          total_cents: non_neg_integer(),
          paid_cents: non_neg_integer()
        }

  @spec balance_cents(t()) :: integer()
  def balance_cents(%__MODULE__{} = invoice), do: invoice.total_cents - invoice.paid_cents
end

invoice = struct!(TypesGuide.Invoice, id: "inv-1001", total_cents: 5_000)
5_000 = TypesGuide.Invoice.balance_cents(invoice)
```

A struct enforces its keys. It does not check the type of a value, so `total_cents: "lots"` builds without complaint. Use a schema where that matters.

## Move a union to tagged values

A discriminated union is the closest TypeScript form to common Elixir style. A tuple or map with a tag takes the place of the `kind` field, and function clauses take the place of the `switch`.

```typescript
type Payment =
  | { kind: "card"; last4: string }
  | { kind: "wire"; iban: string };

function describe(payment: Payment): string {
  switch (payment.kind) {
    case "card":
      return `Card ending ${payment.last4}`;
    case "wire":
      return `Wire from ${payment.iban}`;
  }
}
```

```elixir
defmodule TypesGuide.Payments do
  @type payment :: {:card, last4 :: String.t()} | {:wire, iban :: String.t()}

  @spec describe(payment()) :: String.t()
  def describe({:card, last4}), do: "Card ending #{last4}"
  def describe({:wire, iban}), do: "Wire from #{iban}"
end

"Card ending 4242" = TypesGuide.Payments.describe({:card, "4242"})

:no_clause =
  try do
    TypesGuide.Payments.describe({:cash, "100"})
  rescue
    FunctionClauseError -> :no_clause
  end
```

`tsc` can tell you at build time that a `switch` misses a case. In Elixir a missing clause usually shows up as `FunctionClauseError` at runtime, so tests cover each variant.

## Move a Zod schema to Joi

`Jido.Joi` is the schema module Jido uses everywhere. It is a facade over the Zoi Elixir library, and it is separate from the npm package named `joi`. Its builder style will look familiar if you know Zod.

```typescript
import { z } from "zod";

const OrderLine = z.object({
  sku: z.string().min(1),
  quantity: z.number().int().min(1),
  note: z.string().optional(),
  channel: z.enum(["web", "phone"]).default("web"),
});

const line = OrderLine.parse({ sku: "A-1", quantity: 2 });
```

```elixir
alias Jido.Joi

order_line =
  Joi.object(%{
    sku: Joi.string() |> Joi.min(1),
    quantity: Joi.integer() |> Joi.min(1),
    note: Joi.string() |> Joi.optional(),
    channel: Joi.enum(["web", "phone"]) |> Joi.default("web")
  })

{:ok, %{sku: "A-1", quantity: 2, channel: "web"}} =
  Joi.parse(order_line, %{sku: "A-1", quantity: 2})
```

`Jido.Joi.parse/3` returns a result tuple, which plays the part of Zod's `safeParse`. `Jido.Joi.parse!/3` raises `Jido.Joi.ParseError`, like Zod's `parse`.

```elixir
alias Jido.Joi

{:error, issues} = Joi.parse(order_line, %{sku: "", quantity: 2})

[%{code: :greater_than_or_equal_to, path: [:sku]}] = issues
"too small: must have at least 1 character(s), at sku" = Joi.prettify_errors(issues)
```

| Zod | `Jido.Joi` | Differences |
| --- | --- | --- |
| `z.object({...})` | `object/2` | Keeps unknown keys by default. See below |
| `z.string()`, `z.boolean()` | `string/0`, `boolean/0` | |
| `z.number().int()` | `integer/0` | |
| `z.number()` | `number/0`, `float/0` | |
| `z.array(t)` | `list/1` | |
| `z.literal(v)` | `literal/1` | |
| `z.enum([...])` | `enum/1` | Values can be atoms or strings |
| `z.union([...])` | `union/1` | |
| `z.discriminatedUnion("kind", [...])` | `discriminated_union/2` | |
| `.optional()` | `optional/1` | The key can be absent. `nil` is rejected |
| `.nullable()` | `nullable/1` | The key is required. `nil` is accepted |
| `.default(v)` | `default/2` | |
| `.min(n)`, `.max(n)` | `min/2`, `max/2` | |
| `.refine(fn)`, `.transform(fn)` | `refine/2`, `transform/2` | Action schemas need `{Module, :function, args}` |
| `z.coerce.number()` | `integer(coerce: true)` | |
| `.strict()` | `unrecognized_keys: :error` | |
| `z.infer<typeof T>` | `type_spec/1` | Produces an Elixir typespec |
| `z.toJSONSchema(T)` | `to_json_schema/1` | |

A discriminated union reads the same way:

```elixir
alias Jido.Joi

payment =
  Joi.discriminated_union(:kind, [
    Joi.object(%{kind: Joi.literal("card"), last4: Joi.string()}),
    Joi.object(%{kind: Joi.literal("wire"), iban: Joi.string()})
  ])

{:ok, %{kind: "card", last4: "4242"}} = Joi.parse(payment, %{kind: "card", last4: "4242"})
{:error, [%{message: "unknown discriminator 'cash' for field 'kind'"}]} = Joi.parse(payment, %{kind: "cash"})
```

### Unknown keys stay by default

`z.object` removes unknown keys from its result. `Jido.Joi.object/2` keeps them unchecked, and it never removes a key. Set `unrecognized_keys: :error` to get the behavior of `.strict()`.

```elixir
alias Jido.Joi

open = Joi.object(%{order_id: Joi.string()})
closed = Joi.object(%{order_id: Joi.string()}, unrecognized_keys: :error)

{:ok, %{order_id: "o-1", extra: true}} = Joi.parse(open, %{order_id: "o-1", extra: true})
{:error, [%{code: :unrecognized_key}]} = Joi.parse(closed, %{order_id: "o-1", extra: true})
```

## Validate JSON at a boundary

JSON decodes to string keys, and a field declared as `sku:` is an atom key. Without help, the field reads as missing.

```elixir
alias Jido.Joi

body = JSON.decode!(~s({"sku": "A-1", "quantity": "2", "address": {"city": "Oslo"}, "note": "gift"}))

{:error, [%{code: :required, path: [_field]} | _rest]} = Joi.parse(order_line, body)
```

Set `coerce: true` on each `object/2` level to read string keys as the declared atom keys, and on a field to convert its value. A nested object without `coerce: true` reports its fields as missing.

```elixir
alias Jido.Joi

checkout =
  Joi.object(
    %{
      sku: Joi.string(),
      quantity: Joi.integer(coerce: true),
      address: Joi.object(%{city: Joi.string()}, coerce: true)
    },
    coerce: true
  )

{:ok, %{:sku => "A-1", :quantity => 2, :address => %{city: "Oslo"}, "note" => "gift"}} =
  Joi.parse(checkout, body)
```

The undeclared `"note"` stays a string key, so input creates no new atoms.

## Validate an Action's input and output

In TypeScript you might wrap a function so that it parses its input and output. An Action declares both, and `Jido.Exec.run/4` applies them. Input failures never reach `run/2`.

```typescript
const QuoteInput = z.object({ quantity: z.number().int().min(1) });
const QuoteOutput = z.object({ totalCents: z.number().int() });

function quoteOrder(raw: unknown) {
  const input = QuoteInput.parse(raw);
  return QuoteOutput.parse({ totalCents: input.quantity * 250 });
}
```

```elixir
defmodule TypesGuide.QuoteOrder do
  use Jido.Action,
    name: "types_guide_quote_order",
    schema: Jido.Joi.object(%{quantity: Jido.Joi.integer() |> Jido.Joi.min(1)}, coerce: true),
    output_schema: Jido.Joi.object(%{total_cents: Jido.Joi.integer()})

  @impl true
  def run(%{quantity: quantity}, _context), do: {:ok, %{total_cents: quantity * 250}}
end

{:ok, %{total_cents: 500}} = Jido.Exec.run(TypesGuide.QuoteOrder, %{"quantity" => 2})

{:error, %Jido.Error.ValidationError{details: %{errors: [%{path: [:quantity]}]}}} =
  Jido.Exec.run(TypesGuide.QuoteOrder, %{quantity: 0})
```

Read `code` and `path` from `details.errors` in program logic. [Schemas and Validation](../actions/schemas-validation.md) covers the rest of the Action rules, including why schemas must be static module data.

## Agent state is closed

A TypeScript state type says what fields state has, and a stray field fails the build at the point where you assign an object literal. An Agent `state` schema does the same job at runtime. After each Turn, Jido checks the whole next state against the schema, with a closed boundary. Unknown keys fail, unlike the open `object/2` default for parsing.

```elixir
defmodule TypesGuide.Counter do
  use Jido.Agent, name: "types_guide_counter"

  state do
    schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/inventory/counter"

    route "counter.stray", as: :stray do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        {:ok, Map.put(context.agent_state, :stray, true)}
      end
    end
  end
end

counter = TypesGuide.Counter.instantiate!(id: "c-1")

{:error, %Jido.Error.ValidationError{code: :invalid_state}} =
  TypesGuide.Counter.cmd(counter, TypesGuide.Counter.stray_signal!(%{}))
```

See [Agent State and Schemas](../agents/agent-state-and-schemas.md).

## Derive a typespec

`z.infer` derives a static type from a schema. `Jido.Joi.type_spec/1` returns the same schema as a typespec, which you can place in a `@type` for Dialyzer and generated documentation.

```elixir
defmodule TypesGuide.Shipment do
  @schema Jido.Joi.object(%{tracking_id: Jido.Joi.string(), weight_kg: Jido.Joi.integer()})
  @type t :: unquote(Jido.Joi.type_spec(@schema))

  def schema, do: @schema
end

"%{required(:tracking_id) => binary(), required(:weight_kg) => integer()}" =
  TypesGuide.Shipment.schema() |> Jido.Joi.type_spec() |> Macro.to_string()
```

## Publish a contract to TypeScript

A TypeScript client cannot read an Elixir schema, but both sides can read JSON Schema. `Jido.Joi.to_json_schema/1` projects a schema, and every Action's `authoring_contract/0` holds JSON Schema for its input and output. A JSON Schema to TypeScript generator can then produce client types from that data.

```elixir
%{"input_schema" => %{"properties" => %{"quantity" => %{"type" => "integer", "minimum" => 1}}}} =
  TypesGuide.QuoteOrder.authoring_contract()
```

The projection has limits. Refinements and transforms do not appear in it, and a field with a default appears in `required`. See [Schemas and Validation](../actions/schemas-validation.md#json-schema-projection).

## Next steps

- [Schemas and Validation](../actions/schemas-validation.md) covers Action schemas in full.
- [Jido.Joi Validation](../data/joi-validation.md) covers parsing, initialization, and stored values.
- [Errors and Async](errors-and-async.md) shows how to handle the errors that validation returns.
