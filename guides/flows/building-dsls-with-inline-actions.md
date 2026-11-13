# Inline Action DSLs

Use this guide to give your own compile-time DSL an inline Action body or an embedded Flow. You will build three small hosts with the public `Jido.Action.Inline` and `Jido.Flow.Inline` APIs.

You need these APIs only when you write a macro for other developers. To use inline bodies in a Flow, see [Inline Actions](inline-actions.md).

## How a host works

A host macro does four things at compile time:

1. Parses the declaration with `Jido.Action.Inline.parse_callback!/3` or `Jido.Action.Inline.parse_bound!/3`.
2. Validates any source data it parsed.
3. Calls `Jido.Action.Inline.compile!/4`, which returns `declaration_ast` and `target_ast`.
4. Emits `declaration_ast`, then uses `target_ast` as an ordinary Action target.

The result is a normal Action module. Your host stores that target as it would store any other Action. Its body still runs in the owner module, so it keeps the owner's aliases, attributes, and private functions.

Each declaration has a typed path that identifies it within the owner. The path starts with a `:host` segment, has one or more segments you choose, and ends with a `:role` segment such as `role: :action`. Each segment value is a non-nil atom, string, or integer. A second declaration with the same path raises `CompileError`.

## Build a callback host

In callback mode, the body receives the Action's validated parameters directly, with no source mapping. This host declares invoice rules:

Define and import both declaration arities. A declaration with only a pattern
and a `do` block calls `rule/3`; its third argument contains `do:`. A
declaration with explicit keyword options before the `do` block calls
`rule/4`. The four-argument macro must join `options` and `body` before it calls
`parse_callback!/3`. If the host defines only `rule/3`, the form with options
fails compilation with `undefined function rule/4`.

```elixir
defmodule InvoiceRules do
  alias Jido.Action.Inline

  defmacro __using__(_options) do
    quote do
      use Jido.Action.Inline
      import InvoiceRules, only: [rule: 3, rule: 4]
    end
  end

  defmacro rule(name, pattern, options), do: declaration(name, pattern, options, __CALLER__)

  defmacro rule(name, pattern, options, body),
    do: declaration(name, pattern, options ++ body, __CALLER__)

  def path(name), do: [host: __MODULE__, rule: name, role: :action]

  def run(owner, name, params, context \\ %{}) do
    Jido.Exec.run(Jido.Action.Inline.target!(owner, path(name)), params, context)
  end

  defp declaration(name, pattern, options, caller) do
    parsed = Inline.parse_callback!(pattern, options, caller)
    evaluated_name = Macro.unique_var(:rule_name, __MODULE__)

    compiled =
      Inline.compile!(quote(do: InvoiceRules.path(unquote(evaluated_name))), parsed, caller,
        default_name: evaluated_name,
        remove_imports: [{__MODULE__, [rule: 3, rule: 4]}]
      )

    quote do
      unquote(evaluated_name) = unquote(name)
      unquote(compiled.declaration_ast)
      unquote(compiled.target_ast)
    end
  end
end
```

Two details matter here:

- `default_name:` sets the Action name when the declaration has no `name:` option. Evaluate the name once and share it between the path and the metadata.
- `remove_imports:` removes the host's own macros from the body, so the body cannot declare another rule by accident. Other imports stay available.

An owner uses the host like this:

```elixir
defmodule AcmeInvoiceRules do
  use InvoiceRules

  @late_fee_cents 2500

  rule "late_fee", %{days_late: days_late} do
    {:ok, %{fee_cents: fee(days_late)}}
  end

  rule "discount",
       %{percent: percent},
       name: "acme_discount",
       description: "Converts a discount percentage to a rate.",
       schema: Jido.Joi.object(%{percent: Jido.Joi.integer()}),
       output_schema: Jido.Joi.object(%{rate: Jido.Joi.float()}) do
    {:ok, %{rate: percent / 100}}
  end

  rule "currency", %{amount: amount}, context: ctx do
    {:ok, %{amount: amount, currency: ctx.currency}}
  end

  defp fee(0), do: 0
  defp fee(_days_late), do: @late_fee_cents
end

{:ok, %{fee_cents: 2500}} = InvoiceRules.run(AcmeInvoiceRules, "late_fee", %{days_late: 4})
{:ok, %{rate: 0.2}} = InvoiceRules.run(AcmeInvoiceRules, "discount", %{percent: 20})

{:ok, %{currency: "EUR"}} =
  InvoiceRules.run(AcmeInvoiceRules, "currency", %{amount: 100}, %{currency: "EUR"})
```

The options come from `Jido.Action.Inline.parse_callback!/3`:

| Option | Meaning |
| --- | --- |
| `do:` | The required body. |
| `name:` | Overrides the default public Action name. The path stays the identity. |
| `description:` | Public metadata. Defaults to `nil`. |
| `schema:`, `output_schema:` | Static Action schemas. Both default to `Jido.Joi.map()`. Patterns do not infer schemas. |
| `context:` | A named variable bound to the callback context, without adding a parameter. It cannot reuse a pattern variable. |

The header takes a named variable or a map pattern. To let authors write several function heads, pass `nil` as the pattern and give a body of only `->` clauses. Clause heads can use `when`.

```elixir
defmodule AcmeTaxRules do
  use InvoiceRules

  rule "tax", nil do
    %{region: "EU", cents: cents} -> {:ok, %{tax_cents: div(cents, 5)}}
    %{cents: cents} when cents < 1000 -> {:ok, %{tax_cents: 0}}
    %{cents: cents} -> {:ok, %{tax_cents: div(cents, 10)}}
  end
end

{:ok, %{tax_cents: 200}} = InvoiceRules.run(AcmeTaxRules, "tax", %{region: "EU", cents: 1000})
{:ok, %{tax_cents: 0}} = InvoiceRules.run(AcmeTaxRules, "tax", %{region: "US", cents: 500})
```

The Flow DSL rejects `->` clause bodies. This form is available to your host.

## Build a bound host

In bound mode, the header maps your host's source data into Action parameters, as a Flow Step does. Your host owns that source language. `Jido.Action.Inline.parse_bound!/3` returns the source as unevaluated AST in `params_ast`. You must parse and validate it before you call `Jido.Action.Inline.compile!/4`.

This host binds invoice fields with `field(:name)` and rejects unknown fields at compile time:

```elixir
defmodule InvoiceFields do
  alias Jido.Action.Inline

  @fields [:amount, :customer]

  defmacro __using__(_options) do
    quote do
      use Jido.Action.Inline
      import InvoiceFields, only: [calculation: 3]
      Module.register_attribute(__MODULE__, :invoice_sources, accumulate: true)
      @before_compile InvoiceFields
    end
  end

  defmacro __before_compile__(env) do
    sources = env.module |> Module.get_attribute(:invoice_sources) |> Map.new()

    quote do
      def __invoice_sources__, do: unquote(Macro.escape(sources))
    end
  end

  defmacro calculation(name, bindings, options) do
    caller = __CALLER__
    parsed = Inline.parse_bound!(bindings, options, caller)

    # Validate host data before compile! can create an Action.
    source = parse_source!(parsed.params_ast, caller)
    evaluated_name = Macro.unique_var(:calculation_name, __MODULE__)

    compiled =
      Inline.compile!(quote(do: InvoiceFields.path(unquote(evaluated_name))), parsed, caller,
        default_name: evaluated_name,
        remove_imports: [{__MODULE__, [calculation: 3]}]
      )

    quote do
      unquote(evaluated_name) = unquote(name)
      unquote(compiled.declaration_ast)
      @invoice_sources {unquote(evaluated_name), unquote(Macro.escape(source))}
      unquote(compiled.target_ast)
    end
  end

  def path(name), do: [host: __MODULE__, calculation: name, role: :action]

  def run(owner, name, invoice) do
    params = Map.new(owner.__invoice_sources__()[name], fn {key, field} -> {key, invoice[field]} end)
    Jido.Exec.run(Jido.Action.Inline.target!(owner, path(name)), params)
  end

  defp parse_source!({:%{}, _meta, pairs}, caller) do
    Map.new(pairs, fn
      {key, {:field, _meta, [field]}} when field in @fields ->
        {key, field}

      {_key, other} ->
        raise CompileError,
          file: caller.file,
          line: caller.line,
          description: "unsupported invoice source: " <> Macro.to_string(other)
    end)
  end
end

defmodule AcmeCalculations do
  use InvoiceFields

  calculation "label", [amount <- field(:amount), customer <- field(:customer)] do
    {:ok, %{label: customer <> ": " <> Integer.to_string(amount)}}
  end
end

{:ok, %{label: "Ada: 900"}} =
  InvoiceFields.run(AcmeCalculations, "label", %{amount: 900, customer: "Ada"})
```

`Jido.Action.Inline.parse_bound!/3` accepts the same header forms as a Flow Step: a named binding, a binding list, a sole map pattern, or `[]`. It rejects duplicate names, mixed map and named bindings, a bare `_`, pins, guards, and top-level struct patterns. For a sole map pattern, `params_ast` is the source expression itself, so a full host must also handle that shape.

To let source data use calculations, parse it with `Jido.Expr.parse/2` and a `:leaf_parser`. See [Expressions](flow-expressions.md#reuse-the-grammar-in-a-host-dsl).

## Look up a target

`Jido.Action.Inline.target!/2` returns the Action for an exact path:

```elixir
target = Jido.Action.Inline.target!(AcmeCalculations, InvoiceFields.path("label"))

"label" = target.name()
{:ok, %{label: "Ada: 1"}} = Jido.Exec.run(target, %{amount: 1, customer: "Ada"})
```

Lookup works only after the owner compiles. It raises `ArgumentError` for an invalid or unknown path, and for an owner that is still compiling. It does not compile code, run a body, or create atoms.

## Embed a Flow

`Jido.Flow.Inline` does the same job for a complete Flow. It creates a normal Flow module from standard `use Jido.Flow` options and the contents of a `flow do` block. The path must have at least three segments and end with `role: :flow`.

```elixir
defmodule BillingWorkflows do
  defmacro __using__(_options) do
    quote do
      use Jido.Flow.Inline
      import BillingWorkflows, only: [workflow: 3]
    end
  end

  defmacro workflow(name, options, do: body) do
    path = quote(do: BillingWorkflows.path(unquote(name)))
    compiled = Jido.Flow.Inline.compile!(path, options, body, __CALLER__)

    quote do
      unquote(compiled.declaration_ast)
      unquote(compiled.target_ast)
    end
  end

  def path(name), do: [host: __MODULE__, workflow: name, role: :flow]
end

defmodule AcmeBilling do
  use BillingWorkflows

  workflow "invoice_total", name: "invoice_total" do
    step "total", [amount <- input(:amount), fee <- input(:fee)] do
      {:ok, %{total: amount + fee}}
    end

    output result("total")
  end
end

target = Jido.Flow.Inline.target!(AcmeBilling, BillingWorkflows.path("invoice_total"))

"invoice_total" = target.name()
{:ok, %{total: 110}} = Jido.Exec.run(target, %{amount: 100, fee: 10})
```

The embedded body compiles in the generated Flow module, so it differs from an inline Action body:

- It cannot use the owner's attributes or private functions. Put reusable code in Actions or [Flow Extensions](flow-modules.md).
- It can use extensions configured in the options.
- The path and options evaluate once in the owner, at the declaration.
- If its body fails to compile on recompilation, the previous target is not restored for new calls.

## Rules for every host

- All inputs to these compile-time functions are trusted source code. Do not pass runtime or stored code to them.
- Generated module names are implementation details. Use `target!/2` to find a target.
- Deploy the owner and its generated modules together. A path identifies a declaration, not a code version.
- The owner reserves `__jido_inline_actions__/0` or `__jido_inline_flows__/0`, so it cannot define them.
- Call `Jido.Action.Inline.compile!/4` and `Jido.Flow.Inline.compile!/4` only while the owner module compiles, outside any function. Other calls raise `CompileError`.
