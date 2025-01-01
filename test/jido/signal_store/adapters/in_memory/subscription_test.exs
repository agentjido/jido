defmodule Jido.SignalStore.Adapters.InMemory.SubscriptionTest do
  alias Jido.SignalStore.Adapters.InMemory

  use Jido.SignalStore.InMemoryTestCase
  use Jido.SignalStore.SubscriptionTestCase, event_store: InMemory

  defp event_store_wait(_default \\ nil), do: 1
end
