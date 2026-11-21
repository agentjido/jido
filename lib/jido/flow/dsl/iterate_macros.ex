defmodule Jido.Flow.DSL.IterateMacros do
  @moduledoc false

  alias Jido.Flow.DSL.Authoring

  defmacro state(schema, options) do
    Authoring.entity(
      [schema],
      options,
      extension_module(["Flow", "Iterate", "State"]),
      :__state__,
      __CALLER__,
      {"Iterate state", "Iterate state"}
    )
  end

  defp extension_module(segments),
    do: Module.concat(["Jido", "Flow", "DSL", "Extension" | segments])
end
