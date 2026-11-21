defmodule InlineConsumer.Steps do
  use Jido.Flow, name: "inline_steps"
  require InlineConsumer.BodyMacro
  @step_name "first"

  flow do
    step @step_name, value <- input(:value) do
      {:ok, %{value: InlineConsumer.BodyMacro.increment(value)}}
    end

    step "second", value <- result("first", :value) do
      {:ok, %{value: value * 2}}
    end

    output result("second")
  end
end
