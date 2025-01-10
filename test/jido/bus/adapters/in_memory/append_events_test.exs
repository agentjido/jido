defmodule Jido.Bus.Adapters.InMemory.AppendSignalsTest do
  alias Jido.Bus.Adapters.InMemory

  use Jido.Bus.InMemoryTestCase
  use Jido.Bus.AppendSignalsTestCase, signal_store: InMemory
end
