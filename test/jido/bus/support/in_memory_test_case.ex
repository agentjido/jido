defmodule Jido.Bus.InMemoryTestCase do
  use ExUnit.CaseTemplate

  alias Jido.Bus.Adapters.InMemory
  alias Jido.Serialization.JsonSerializer

  setup do
    {:ok, child_spec, signal_store_meta} =
      InMemory.child_spec(InMemory, serializer: JsonSerializer)

    for child <- child_spec do
      start_supervised!(child)
    end

    [signal_store_meta: signal_store_meta]
  end
end
