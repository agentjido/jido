defmodule Jido.Bus.Adapters.InMemory.SubscriptionTest do
  alias Jido.Bus.Adapters.InMemory

  use Jido.Bus.InMemoryTestCase
  use Jido.Bus.SubscriptionTestCase, signal_store: InMemory

  defp signal_store_wait(_default \\ nil), do: 1
end
