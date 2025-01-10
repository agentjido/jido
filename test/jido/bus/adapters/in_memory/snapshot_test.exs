defmodule Jido.Bus.Adapters.InMemory.SnapshotTest do
  alias Jido.Bus.Adapters.InMemory

  use Jido.Bus.InMemoryTestCase
  use Jido.Bus.SnapshotTestCase, signal_store: InMemory
end
