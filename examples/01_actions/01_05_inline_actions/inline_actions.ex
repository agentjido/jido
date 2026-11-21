defmodule Jido.Examples.Actions.InlineActions.Host do
  alias Jido.Action.Inline

  defmacro __using__(_options) do
    quote do
      use Jido.Action.Inline
      import Jido.Examples.Actions.InlineActions.Host, only: [inline_action: 3, inline_action: 4]
    end
  end

  defmacro inline_action(name, pattern, options) do
    declaration(name, pattern, options, __CALLER__)
  end

  defmacro inline_action(name, pattern, options, body) do
    declaration(name, pattern, options ++ body, __CALLER__)
  end

  defp declaration(name, pattern, options, caller) do
    parsed = Inline.parse_callback!(pattern, options, caller)

    compiled =
      Inline.compile!(
        [host: __MODULE__, declaration: name, role: :action],
        parsed,
        caller,
        default_name: name
      )

    compiled.declaration_ast
  end

  def target!(owner, name) do
    Inline.target!(owner, host: __MODULE__, declaration: name, role: :action)
  end
end

defmodule Jido.Examples.Actions.InlineActions.Greeting do
  use Jido.Examples.Actions.InlineActions.Host

  inline_action "greet", %{name: name},
    schema: Jido.Joi.object(%{name: Jido.Joi.string() |> Jido.Joi.min(1)}),
    output_schema: Jido.Joi.object(%{message: Jido.Joi.string()}),
    context: context do
    {:ok, %{message: context.prefix <> name}}
  end

  def run(params, context) do
    target = Jido.Examples.Actions.InlineActions.Host.target!(__MODULE__, "greet")
    Jido.Exec.run(target, params, context)
  end
end
