defmodule Jido.Exec.ContinuationTest do
  use ExUnit.Case, async: true

  alias Jido.Exec.Continuation
  alias JidoTest.DurableFixtures, as: F

  defp signal, do: Jido.Signal.new!("continuation.test", %{value: 1}, source: "/test")

  test "a direct Flow continuation is portable and has one stable identity" do
    assert {:ok, continuation} =
             Continuation.running(%{
               id: "turn-1",
               signal: signal(),
               admitted_signal: signal(),
               context: %{tenant: "one"},
               plugin_inputs: %{},
               target: F.Flow,
               expires_at: 100
             })

    assert continuation.id == "turn-1"
    assert continuation.status == :running
    assert continuation.fingerprint == Continuation.fingerprint(F.Flow)
    assert :ok = Continuation.validate(continuation)
    assert :ok = Continuation.portable(continuation)

    completed = Continuation.put_status!(continuation, :completed)
    assert completed.id == continuation.id
    assert completed.status == :completed
  end

  test "a Handoff gains resume data only when it is released" do
    instruction = Jido.Instruction.new!(target: F.Step, params: %{step: 1, value: 0})

    assert {:ok, accepted} =
             Continuation.accept_handoff(%{
               id: "turn-2",
               signal: signal(),
               context: %{},
               instruction: instruction,
               chain_id: "chain-1",
               chain_order: 2,
               predecessor_id: "turn-1"
             })

    refute Map.has_key?(accepted, :admitted_signal)
    assert :ok = Continuation.compatible(accepted, instruction)

    assert {:ok, released} =
             Continuation.release_handoff(accepted, %{
               admitted_signal: signal(),
               plugin_inputs: %{},
               expires_at: :infinity
             })

    assert released.status == :released
    assert released.id == accepted.id
    assert released.predecessor_id == "turn-1"
    assert :ok = Continuation.validate(released)
    assert :ok = Continuation.portable(released)
  end

  test "continuation validation rejects unknown and incomplete data" do
    assert {:error, _} = Continuation.validate(%{})

    assert {:error, _} =
             Continuation.running(%{
               id: "",
               signal: signal(),
               admitted_signal: signal(),
               context: %{},
               plugin_inputs: %{},
               target: F.Flow,
               expires_at: 100
             })
  end
end
