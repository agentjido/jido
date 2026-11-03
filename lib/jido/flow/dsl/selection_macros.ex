defmodule Jido.Flow.DSL.SelectionMacros do
  @moduledoc false

  alias Jido.Flow.DSL.Authoring

  defmacro timer(name, options) do
    Authoring.entity(
      [name],
      options,
      extension_module(["Flow", "Selection", "TimerOption"]),
      :__timer_option__,
      __CALLER__,
      {"Selection timer", "one Selection timer"}
    )
  end

  defmacro await(name, options) do
    Authoring.entity(
      [name],
      options,
      extension_module(["Flow", "Selection", "AwaitOption"]),
      :__await_option__,
      __CALLER__,
      {"Selection await", "one Selection await"}
    )
  end

  defp extension_module(segments),
    do: Module.concat(["Jido", "Flow", "DSL", "Extension" | segments])
end
