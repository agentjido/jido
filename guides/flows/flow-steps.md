# Steps and Output

Use this guide to declare a Step in any of its forms, build a Flow result with `output`, and look up what each component returns.

## Declare a Step

A Step calls one target. It has three source forms, and all three produce a call component in the canonical Flow.

```elixir
defmodule FlowSteps.Normalize do
  use Jido.Action, name: "flow_steps_normalize"

  @impl true
  def run(%{email: email}, _context), do: {:ok, %{email: String.downcase(email)}}
end

defmodule FlowSteps.Signup do
  use Jido.Flow, name: "flow_steps_signup"

  flow do
    # Keyword form
    step "normalize",
      action: FlowSteps.Normalize,
      params: %{email: input(:email)}

    # Field-block form
    step "normalize_again" do
      action FlowSteps.Normalize
      params %{email: result("normalize", :email)}
      meta %{owner: "signup"}
    end

    # Inline form
    step "welcome", email <- result("normalize_again", :email) do
      {:ok, %{message: "Welcome, " <> email}}
    end

    output result("welcome")
  end
end

{:ok, %{message: "Welcome, ada@example.com"}} =
  Jido.Exec.run(FlowSteps.Signup, %{email: "ADA@EXAMPLE.COM"})
```

Choose the keyword form for a short call and the field-block form when the fields read better on separate lines. Do not mix the two in one Step. Use the inline form for a small operation that has no other caller. [Inline Actions](inline-actions.md) covers that form in full.

## Step fields

| Field | Required | Meaning |
| --- | --- | --- |
| name (first argument) | yes | The component name, unique within the Flow. An atom or a non-blank string of up to 256 bytes. |
| `action` | yes | An Action module, or a Flow module for a child Flow. |
| `params` | yes | A Flow value that builds the target's input. |
| `needs` | no | A name or list of names to run after, with no data transfer. Defaults to `[]`. |
| `meta` | no | A map of author metadata. It does not change execution. Defaults to `%{}`. |

`params` is usually a map of references, but it can be any Flow value. `input()` passes the complete Flow input:

```elixir
defmodule FlowSteps.PassThrough do
  use Jido.Flow, name: "flow_steps_pass_through"

  flow do
    step "normalize", action: FlowSteps.Normalize, params: input()
    output result("normalize")
  end
end

{:ok, %{email: "ada@example.com"}} =
  Jido.Exec.run(FlowSteps.PassThrough, %{email: "Ada@Example.com"})
```

The target validates its input with its own schema, so a Step failure carries the Action's validation error. See [Schemas and Validation](../actions/schemas-validation.md).

A component name can come from a module attribute or another compile-time expression. It evaluates once at the declaration.

## Declare the output

`output` builds the Flow result from references, literal data, and expressions. It takes one value and has no keyword or field-block form.

```elixir
defmodule FlowSteps.Receipt do
  use Jido.Flow,
    name: "flow_steps_receipt",
    output_schema: Jido.Joi.object(%{email: Jido.Joi.string(), source: Jido.Joi.atom()})

  flow do
    step "normalize", action: FlowSteps.Normalize, params: %{email: input(:email)}

    output %{
      email: result("normalize", :email),
      source: :signup
    }
  end
end

{:ok, %{email: "ada@example.com", source: :signup}} =
  Jido.Exec.run(FlowSteps.Receipt, %{email: "ADA@example.com"})
```

These rules apply:

- `output` is required and cannot be `nil`. Both cases raise `CompileError` with "Flow output is required".
- It must be the last declaration, or the compiler raises "output must be the final Flow declaration".
- The resolved value must be a map or a `Jido.Action.Output` envelope. Any other value compiles, then fails at runtime in the `:flow_output` phase.
- When the Flow sets `output_schema`, Exec validates the resolved output against it.

To return a value that is not a map, return an explicit envelope from an Action. See [Outputs and Effects](../actions/action-effects.livemd).

```elixir
defmodule FlowSteps.RawReceipt do
  use Jido.Flow, name: "flow_steps_raw_receipt"

  flow do
    step "render", email <- input(:email) do
      {:ok, Jido.Action.Output.raw("Receipt for " <> email)}
    end

    output result("render")
  end
end

{:ok, %Jido.Action.Output{kind: :raw, value: "Receipt for ada@example.com"}} =
  Jido.Exec.run(FlowSteps.RawReceipt, %{email: "ada@example.com"})
```

## What each component returns

`result("name")` reads the value in this table, and `result("name", path)` reads inside it.

| Component | Result |
| --- | --- |
| `step` | The Action result. |
| `step` with a Flow target | The child Flow's output. |
| `choice` | The result of the selected option's Action, or of the fallback. |
| `map` | An ordered list of Action results. With `on_error: :collect_errors`, a list of `%{status: :ok, value: result}` and `%{status: :error, error: error_map}` records. |
| `reduce` | The final accumulator. |
| `parallel` | An ordered list of `%{name: name, value: result}`. With `on_error: :collect_errors`, each entry also has `status`, and failed entries have `error` in place of `value`. |
| `iterate` | `%{kind: :jido_flow_iterate_result, iterations: count, state: state, output: last_body_result}` |
| `invoke` | The expander result, or the result of the target it selects. |
| `handoff` | The successor request. The output must be this complete result. |

## Next steps

- [Inline Actions](inline-actions.md) lists the binding forms and body rules.
- [References and Data](flow-references.livemd) covers what a `params` or `output` value can read.
- [Flow Data Definitions](../flow-data/flow-data.md) shows the equivalent map form.
