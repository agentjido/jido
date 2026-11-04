defmodule InlineConsumer.BodyMacro do
  defmacro increment(value), do: quote(do: unquote(value) + 100)
end
