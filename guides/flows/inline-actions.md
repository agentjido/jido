# Inline Actions

Use an inline body when a small operation belongs to one Flow and needs no module of its own. This guide lists the binding forms, the body scope, the settings, and the limits.

An inline body is an Action. The compiler generates a normal Action module for it, so it follows the same validation, result, and failure rules as a module you write. The body runs as a function of the module that declares the Flow.

## Bind inputs

The header says which Flow data the body receives. The right side of `<-` is a Flow reference or literal data.

```elixir
defmodule InlineGuide.Bindings do
  use Jido.Flow, name: "inline_guide_bindings"

  flow do
    # No input
    step "invoice_number", [] do
      {:ok, %{number: "INV-100"}}
    end

    # One named binding
    step "customer", name <- input(:name) do
      {:ok, %{name: String.trim(name)}}
    end

    # A list for two or more bindings
    step "label", [number <- result("invoice_number", :number), name <- result("customer", :name)] do
      {:ok, %{label: number <> " for " <> name}}
    end

    # A sole map pattern receives the source as its complete parameters
    step "billing", %{city: city} <- input(:address) do
      {:ok, %{city: city}}
    end

    output %{label: result("label", :label), city: result("billing", :city)}
  end
end

{:ok, %{label: "INV-100 for Ada", city: "London"}} =
  Jido.Exec.run(InlineGuide.Bindings, %{name: " Ada ", address: %{city: "London"}})
```

A named binding adds one atom key to the Action parameters, so `name <- input(:name)` supplies `%{name: value}`. `[]` supplies `%{}`.

The compiler rejects these headers with a `CompileError`:

| Header | Fix |
| --- | --- |
| Two bindings without a list | Wrap them in a list. |
| A map pattern with other bindings | Use one or the other. |
| A duplicate name | Rename one binding. |
| A bare `_` | Use a named variable or `[]`. |
| A pin, a guard, or a top-level struct pattern | Bind by name and match inside the body. |
| A function call or operator on the right of `<-` | Do the calculation in the body. |
| `->` clauses as the body | Write a `case` inside the body. |

## Write the body

The body is normal Elixir. It returns any Action result, such as `{:ok, map}` or `{:error, reason}`. It runs in the owning module, so it can call private functions and read module attributes.

```elixir
defmodule InlineGuide.Scope do
  use Jido.Flow, name: "inline_guide_scope"

  @late_fee_cents 2500

  flow do
    step "invoice", [days_late <- input(:days_late), amount <- input(:amount)] do
      case days_late do
        0 -> {:ok, %{due: amount}}
        _days -> {:ok, %{due: with_fee(amount)}}
      end
    end

    output result("invoice")
  end

  defp with_fee(amount), do: amount + @late_fee_cents
end

{:ok, %{due: 10_000}} = Jido.Exec.run(InlineGuide.Scope, %{days_late: 0, amount: 10_000})
{:ok, %{due: 12_500}} = Jido.Exec.run(InlineGuide.Scope, %{days_late: 3, amount: 10_000})
```

The Flow DSL declarations are not imported inside the body, so a local variable or function named `map` or `step` behaves as normal Elixir.

A header pattern that does not match fails the Step with an execution error. It does not act as schema validation. Add a `schema:` setting when you want a validation error instead.

## Read context

Context is not implicit. There are two ways to read it:

```elixir
defmodule InlineGuide.Context do
  use Jido.Flow, name: "inline_guide_context"

  flow do
    # As a named parameter
    step "tenant", tenant <- context(:tenant) do
      {:ok, %{tenant: tenant}}
    end

    # As the Action callback's context argument
    step "currency", [], inline: [context: ctx] do
      {:ok, %{currency: ctx.currency}}
    end

    output %{tenant: result("tenant", :tenant), currency: result("currency", :currency)}
  end
end

{:ok, %{tenant: "acme", currency: "EUR"}} =
  Jido.Exec.run(InlineGuide.Context, %{}, %{tenant: "acme", currency: "EUR"})
```

`context(:tenant)` adds a parameter that the Action's schema sees. `inline: [context: ctx]` binds the callback context without changing parameters or schemas. The variable cannot reuse a name from the header pattern.

See [Action Context](../actions/action-context.md) for what context holds.

## Configure the generated Action

`inline:` sets the Action's metadata and schemas. Without it, the Action name is the Step name, and both schemas accept any map.

| Setting | Meaning |
| --- | --- |
| `name` | The Action's public name. |
| `description` | The Action's description. Defaults to `nil`. |
| `schema` | The input schema. It runs before the body's pattern matches and applies defaults. |
| `output_schema` | The output schema. |
| `context` | A variable bound to the callback context. |

Keep `needs:` and `meta:` at the Step level, outside `inline:`. Other Step fields are rejected with "use only needs:, meta:, inline:, and do:".

```elixir
defmodule InlineGuide.Settings do
  use Jido.Flow, name: "inline_guide_settings"

  flow do
    step "prepare", [] do
      {:ok, %{ready: true}}
    end

    step "discount", percent <- input(:percent),
      needs: "prepare",
      meta: %{owner: "billing"},
      inline: [
        name: "apply_discount",
        description: "Validates a discount percentage.",
        schema: Jido.Joi.object(%{percent: Jido.Joi.integer()}),
        output_schema: Jido.Joi.object(%{rate: Jido.Joi.float()})
      ] do
      {:ok, %{rate: percent / 100}}
    end

    output result("discount")
  end
end

{:ok, %{rate: 0.15}} = Jido.Exec.run(InlineGuide.Settings, %{percent: 15})
{:error, %Jido.Error.ValidationError{}} = Jido.Exec.run(InlineGuide.Settings, %{percent: "15"})
```

## Where inline bodies work

Inline bodies work in `step` and in a named `action` inside `parallel`. In `parallel`, the only options are `inline:` and `do:`.

Choice targets, `map`, `reduce`, `iterate`, `invoke`, and `handoff` take Action modules. For these, write a module.

## Reuse the Action

After the owning module compiles, `step_action/1` returns the Step's Action target:

```elixir
action = InlineGuide.Settings.step_action("discount")

"apply_discount" = action.name()
{:ok, %{rate: 0.25}} = Jido.Exec.run(action, %{percent: 25})
```

The target keeps only the Action. It drops the Step's parameters, dependencies, and metadata. `step_action/1` also works for Steps with an explicit Action module. It raises `ArgumentError` for an unknown name, a non-Step component, or a Step with a Flow target.

## Deployment

Generated module names are implementation details, so do not write them into code or stored data. Deploy the owning module and its generated modules together. A body edit can keep the same target name and graph identity, so neither one identifies a code version.

Stored Flow JSON and map definitions cannot hold body code. To store a Flow that uses an inline Action, register the target with a trusted Catalog. See [Store Flows as JSON](../flow-data/flow-storage.md).

## Choose a named Action instead

Write a named Action module when the operation has other callers, needs lifecycle hooks, or belongs in your public API. See [Actions](../actions/actions.md).

## Related

- [Inline Action DSLs](building-dsls-with-inline-actions.md) brings this form to your own DSL.
- [Steps and Output](flow-steps.md) covers the other Step forms.
