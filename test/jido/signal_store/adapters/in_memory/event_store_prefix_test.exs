defmodule Jido.SignalStore.Adapters.InMemory.SignalStorePrefixTest do
  alias Jido.SignalStore.Adapters.InMemory

  use Jido.SignalStore.SignalStorePrefixTestCase, event_store: InMemory

  def start_event_store(config) do
    {:ok, child_spec, event_store_meta} = InMemory.child_spec(InMemory, config)

    for child <- child_spec do
      start_supervised!(child)
    end

    {:ok, event_store_meta}
  end
end
