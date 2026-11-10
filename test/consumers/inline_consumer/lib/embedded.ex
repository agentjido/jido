defmodule InlineConsumer.Embedded do
  use Jido.Flow.Inline
  require InlineConsumer.Host

  @path [host: InlineConsumer.Host, declaration: "embedded", role: :flow]
  @target (InlineConsumer.Host.embedded_flow @path, name: "embedded" do
             step "increment", value <- input(:value) do
               {:ok, %{value: value + 10}}
             end

             output result("increment")
           end)

  def target, do: @target
end
