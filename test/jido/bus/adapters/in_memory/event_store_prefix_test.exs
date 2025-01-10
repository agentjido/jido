defmodule Jido.Bus.Adapters.InMemory.BusPrefixTest do
  alias Jido.Bus.Adapters.InMemory

  use Jido.Bus.BusPrefixTestCase, signal_store: InMemory

  def start_signal_store(config) do
    {:ok, child_spec, signal_store_meta} = InMemory.child_spec(InMemory, config)

    for child <- child_spec do
      start_supervised!(child)
    end

    {:ok, signal_store_meta}
  end
end
