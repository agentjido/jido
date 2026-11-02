defmodule InlineConsumer.Host do
  alias Jido.Action.Inline

  defmacro __using__(_) do
    quote do
      use Jido.Action.Inline
      import InlineConsumer.Host
    end
  end

  defmacro action(name, mode, header, options) do
    declaration(name, mode, header, options, __CALLER__)
  end

  defmacro action(name, mode, header, options, body) do
    declaration(name, mode, header, options ++ body, __CALLER__)
  end

  defp declaration(name, mode, header, options, caller) do
    parsed =
      case mode do
        :bound -> Inline.parse_bound!(header, options, caller)
        :callback -> Inline.parse_callback!(header, options, caller)
      end

    compiled =
      Inline.compile!(
        [host: __MODULE__, declaration: name, role: :action],
        parsed,
        caller,
        default_name: name
      )

    quote do
      unquote(compiled.declaration_ast)

      def params(unquote(name), var!(value)),
        do: unquote(parsed.params_ast || quote(do: var!(value)))
    end
  end

  defmacro decorate(value), do: quote(do: "[" <> unquote(value) <> "]")

  def run(owner, name, value, context) do
    target = Inline.target!(owner, host: __MODULE__, declaration: name, role: :action)
    Jido.Exec.run(target, owner.params(name, value), context)
  end
end
