defmodule InlineConsumer.BodyMacro do
  defmacro increment(value), do: quote(do: missing_inline_body_function(unquote(value)))
end
