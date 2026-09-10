defmodule JidoTest.FactoryWriter.Barrier do
  @moduledoc false
  @behaviour Jido.Examples.Factory.FlowFactory.Writer

  @impl true
  def write(%{observer: observer, hold: hold}, input, context) do
    send(observer, {:work, input, self()})

    if hold == true or (is_function(hold, 1) and hold.(input)) do
      receive do
        :release -> :ok
      after
        15_000 -> raise "Worker test barrier was not released"
      end
    end

    client = Map.take(context, [:accept_after, :fail_role])
    Jido.Examples.Factory.FlowFactory.Writer.Local.write(client, input, context)
  end
end
