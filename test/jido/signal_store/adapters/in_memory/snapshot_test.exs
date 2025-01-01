defmodule Jido.SignalStore.Adapters.InMemory.SnapshotTest do
  alias Jido.SignalStore.Adapters.InMemory

  use Jido.SignalStore.InMemoryTestCase
  use Jido.SignalStore.SnapshotTestCase, event_store: InMemory
end
