defmodule Jido.SignalStore.InMemoryTestCase do
  use ExUnit.CaseTemplate

  alias Jido.SignalStore.Adapters.InMemory
  alias Jido.Serialization.JsonSerializer

  setup do
    {:ok, child_spec, event_store_meta} =
      InMemory.child_spec(InMemory, serializer: JsonSerializer)

    for child <- child_spec do
      start_supervised!(child)
    end

    [event_store_meta: event_store_meta]
  end
end
