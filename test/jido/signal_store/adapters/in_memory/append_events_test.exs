defmodule Jido.SignalStore.Adapters.InMemory.AppendEventsTest do
  alias Jido.SignalStore.Adapters.InMemory

  use Jido.SignalStore.InMemoryTestCase
  use Jido.SignalStore.AppendEventsTestCase, event_store: InMemory
end
