# Flow Extensions

Use a Flow extension to add your own macros to `flow do` when a team repeats the same declarations. An extension changes only how you write a Flow. Its macros expand to normal declarations, so the compiled result is the same canonical `Jido.Flow` value.

## Write an extension

Define the macros in a module that uses `Jido.Flow.Extension`, then list that module in `extensions:`. The extension must be compiled before the Flow that uses it.

```elixir
defmodule FlowExt.Notify do
  use Jido.Action, name: "flow_ext_notify"

  @impl true
  def run(%{address: address, template: template}, _context) do
    {:ok, %{sent_to: address, template: template}}
  end
end

defmodule FlowExt.Helpers do
  use Jido.Flow.Extension

  defmacro notify(name, address, template) do
    quote do
      step unquote(name),
        action: FlowExt.Notify,
        params: %{address: unquote(address), template: unquote(template)}
    end
  end
end

defmodule FlowExt.Welcome do
  use Jido.Flow,
    name: "flow_ext_welcome",
    extensions: [FlowExt.Helpers]

  flow do
    notify "welcome", input(:address), "welcome_email"
    output result("welcome")
  end
end

{:ok, %{sent_to: "ada@example.com", template: "welcome_email"}} =
  Jido.Exec.run(FlowExt.Welcome, %{address: "ada@example.com"})
```

A macro's arguments are source AST, so `input(:address)` passes straight into the expanded Step and follows the normal Flow value rules.

## The result is an ordinary Flow

The extended Flow equals one written by hand with the same declarations:

```elixir
defmodule FlowExt.WelcomeByHand do
  use Jido.Flow, name: "flow_ext_welcome"

  flow do
    step "welcome",
      action: FlowExt.Notify,
      params: %{address: input(:address), template: "welcome_email"}

    output result("welcome")
  end
end

true = FlowExt.Welcome.flow() == FlowExt.WelcomeByHand.flow()
```

An extension cannot add a component type, change the canonical value, or add runtime behavior. Stored JSON and map definitions never load or run an extension, so they do not need it. See [Store Flows as JSON](../flow-data/flow-storage.md).

## Expand to any declaration

A macro can expand to any declaration, including an inline Step, `needs:`, and `output`. An inline body in a macro runs in the Flow module, so it can call that module's private functions.

```elixir
defmodule FlowExt.Patterns do
  use Jido.Flow.Extension

  defmacro calculated(name, bindings, do: body) do
    quote do
      step unquote(name), unquote(bindings) do
        unquote(body)
      end
    end
  end

  defmacro audited(name, dependency) do
    quote do
      step unquote(name), [], needs: [unquote(dependency)] do
        {:ok, %{audited: unquote(dependency)}}
      end
    end
  end

  defmacro output_result(name) do
    quote do
      output result(unquote(name))
    end
  end
end

defmodule FlowExt.Invoice do
  use Jido.Flow,
    name: "flow_ext_invoice",
    extensions: [FlowExt.Patterns, FlowExt.Helpers]

  flow do
    calculated "double", amount <- input(:amount) do
      {:ok, %{amount: double(amount)}}
    end

    audited "audit", "double"
    output_result "double"
  end

  defp double(amount), do: amount * 2
end

{:ok, %{amount: 8}} = Jido.Exec.run(FlowExt.Invoice, %{amount: 4})
```

A Flow can list several extensions. An `output` from a macro must still be the last declaration.

## Errors point to the caller

Expanded declarations get the usual validation. An error reports the line of the macro call in the Flow:

```elixir
source = """
defmodule FlowExt.Broken do
  use Jido.Flow,
    name: "flow_ext_broken",
    extensions: [FlowExt.Helpers]

  flow do
    notify "welcome", result("missing"), "welcome_email"
    output result("welcome")
  end
end
"""

%CompileError{line: 7, description: description} =
  try do
    Code.compile_string(source, "broken_flow.ex")
  rescue
    error in CompileError -> error
  end

"Flow reference points to an unknown component" = description
```

## Configuration rules

`extensions:` must be a static list of modules, set once, in `use Jido.Flow`. The compiler rejects these with a `CompileError`:

| Problem | Message |
| --- | --- |
| Not a list | "Flow extensions must be a list" |
| A repeated module | "duplicate Flow extension" |
| A module that does not use `Jido.Flow.Extension` | "Flow extension must use Jido.Flow.Extension" |
| `extensions:` given twice | "Flow extensions can be configured only once" |

`use Jido.Flow.Extension` accepts no options.

## Design an extension

Keep the public API of an extension module to macros. Put helpers for map definitions in another module. Map definitions use normal functions that return Flow data, so they need no extension.

Prefer a plain Action or a child Flow when the repetition is behavior, not syntax. An extension hides declarations from a reader of the Flow, so name macros after what they declare.

## Related

- [Inline Action DSLs](building-dsls-with-inline-actions.md) covers a DSL that lives outside `flow do`.
- [Authoring Runtime Data](../flow-data/authoring-runtime-data.md) covers helpers for map definitions.
