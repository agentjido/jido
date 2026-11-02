defmodule InlineConsumer.Roles do
  use Jido.Flow, name: "inline_flow_steps"
  require InlineConsumer.BodyMacro

  flow do
    step "seed", value <- input(:value), inline: [name: "step"] do
      {:ok, %{value: adjust(value)}}
    end

    step "finish", value <- result("seed", :value), inline: [name: "finish"] do
      {:ok, %{value: adjust(value)}}
    end

    output result("finish")
  end

  defp adjust(value), do: InlineConsumer.BodyMacro.increment(value)
end
