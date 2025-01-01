defmodule Jido.SignalStore.Adapters.InMemoryTest do
  use Jido.SignalStore.InMemoryTestCase

  alias Jido.SignalStore.Adapters.InMemory
  alias Jido.SignalStore.EventData

  defmodule BankAccountOpened do
    @derive Jason.Encoder
    defstruct [:account_number, :initial_balance]
  end

  describe "reset!/0" do
    test "wipes all data from memory", %{event_store_meta: event_store_meta} do
      pid = Process.whereis(InMemory.SignalStore)
      initial = :sys.get_state(pid)
      events = [build_event(1)]

      :ok = InMemory.append_to_stream(event_store_meta, "stream", 0, events)
      after_event = :sys.get_state(pid)

      InMemory.reset!(InMemory)
      after_reset = :sys.get_state(pid)

      assert initial == after_reset
      assert length(Map.get(after_event.streams, "stream")) == 1
      assert after_reset.streams == %{}
    end
  end

  defp build_event(account_number) do
    %EventData{
      causation_id: Jido.Util.generate_id(),
      correlation_id: Jido.Util.generate_id(),
      event_type: "#{__MODULE__}.BankAccountOpened",
      data: %BankAccountOpened{account_number: account_number, initial_balance: 1_000},
      metadata: %{"user_id" => "test"}
    }
  end
end
