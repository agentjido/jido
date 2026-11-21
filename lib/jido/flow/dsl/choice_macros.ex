defmodule Jido.Flow.DSL.ChoiceMacros do
  @moduledoc false

  alias Jido.Flow.DSL.Authoring

  defmacro option(name, options) do
    evaluated_name = Macro.unique_var(:option_name, __MODULE__)

    declaration =
      nested_entity(
        [evaluated_name],
        options,
        extension_module(["Flow", "Choice", "Option"]),
        :__option__,
        __CALLER__
      )

    quote line: __CALLER__.line do
      unquote(evaluated_name) = unquote(name)
      unquote(declaration)
    end
  end

  defmacro otherwise(options) do
    nested_entity(
      [],
      options,
      extension_module(["Flow", "Choice", "Otherwise"]),
      :__otherwise__,
      __CALLER__
    )
  end

  defp nested_entity(arguments, options, module, function, caller) do
    Authoring.entity(
      arguments,
      options,
      module,
      function,
      caller,
      {"Choice declaration", "one Choice target"}
    )
  end

  defp extension_module(segments),
    do: Module.concat(["Jido", "Flow", "DSL", "Extension" | segments])
end
