defmodule Jido.Bus.Adapters.InMemoryTest do
  use Jido.Bus.InMemoryTestCase

  alias Jido.Bus.Adapters.InMemory
  alias Jido.Signal

  defmodule BankAccountOpened do
    @derive Jason.Encoder
    defstruct [:account_number, :initial_balance]
  end

  describe "reset!/0" do
    test "wipes all data from memory", %{signal_store_meta: signal_store_meta} do
      pid = Process.whereis(InMemory.Bus)
      initial = :sys.get_state(pid)
      signals = [build_signal(1)]

      :ok = InMemory.publish(signal_store_meta, "stream", 0, signals)
      after_signal = :sys.get_state(pid)

      InMemory.reset!(InMemory)
      after_reset = :sys.get_state(pid)

      assert initial == after_reset
      assert length(Map.get(after_signal.streams, "stream")) == 1
      assert after_reset.streams == %{}
    end
  end

  defp build_signal(account_number) do
    %Signal{
      id: UUID.uuid4(),
      source: "http://example.com/bank",
      jido_causation_id: UUID.uuid4(),
      jido_correlation_id: UUID.uuid4(),
      type: "#{__MODULE__}.BankAccountOpened",
      data: %BankAccountOpened{account_number: account_number, initial_balance: 1_000},
      metadata: %{"user_id" => "test"}
    }
  end
end
