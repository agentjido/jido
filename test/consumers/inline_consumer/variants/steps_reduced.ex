defmodule InlineConsumer.Steps do
  use Jido.Flow, name: "inline_steps"
  require InlineConsumer.BodyMacro
  @step_name "renamed"

  flow do
    step @step_name, value <- input(:value) do
      {:ok, %{value: InlineConsumer.BodyMacro.increment(value)}}
    end

    output result("renamed")
  end
end
