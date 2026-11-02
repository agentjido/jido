defmodule InlineConsumer.Bound do
  use InlineConsumer.Host
  alias Integer, as: Number

  @offset 1
  action "bound",
         :bound,
         value <- var!(value) * 2,
         schema: Zoi.object(%{value: Zoi.integer()}),
         output_schema: Zoi.object(%{message: Zoi.string()}),
         context: ctx do
    {:ok, %{message: ctx.prefix <> private_helper(value + @offset)}}
  end

  defp private_helper(value), do: decorate(Number.to_string(value))
end

defmodule InlineConsumer.DeclarationHooks do
  defmacro __before_compile__(_env) do
    quote do
      action "late_first", :callback, %{value: value}, context: ctx do
        {:ok, %{message: ctx.prefix <> private_helper(value + 1)}}
      end

      action "late_second", :callback, %{value: value}, context: ctx do
        {:ok, %{message: ctx.prefix <> private_helper(value + 2)}}
      end
    end
  end
end

defmodule InlineConsumer.Callback do
  use InlineConsumer.Host
  @before_compile InlineConsumer.DeclarationHooks

  action "callback", :callback, %{value: value},
    schema: Zoi.object(%{value: Zoi.integer() |> Zoi.default(4)}),
    output_schema: Zoi.object(%{message: Zoi.string()}),
    context: ctx do
    {:ok, %{message: ctx.prefix <> private_helper(value)}}
  end

  defp private_helper(value), do: decorate(Integer.to_string(value))
end
