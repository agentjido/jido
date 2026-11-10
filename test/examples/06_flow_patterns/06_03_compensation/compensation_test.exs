Code.require_file("../../support/loader.exs", __DIR__)

defmodule Jido.Examples.Patterns.CompensationTest do
  use ExUnit.Case, async: false
  @moduletag :example

  setup_all do
    Jido.Test.Examples.Loader.require_source!("06_flow_patterns/06_03_compensation/compensation.ex")

    :ok
  end

  setup do
    ledger = Module.concat(__MODULE__, Ledger)

    start_supervised!(%{
      id: ledger,
      start:
        {Agent, :start_link, [fn -> %{accepted: MapSet.new(), operations: [], reservations: %{}} end, [name: ledger]]}
    })

    %{ledger: ledger}
  end

  test "resumes after reservation and compensates exactly once", %{ledger: ledger} do
    runner = Module.concat(__MODULE__, Runner)
    start_supervised!({Runic.Runner, name: runner})
    id = {:compensation, System.unique_integer([:positive])}
    tag = make_ref()
    owner = self()

    hooks = [
      on_complete: fn _runnable, _duration, _state -> send(owner, {tag, :unit_done}) end,
      on_failed: fn _runnable, _reason, _state -> send(owner, {tag, :unit_done}) end
    ]

    assert {:ok, _worker} =
             Jido.Exec.start(
               runner,
               id,
               Jido.Examples.Patterns.Compensation,
               %{order_id: "order-1", amount: 50, approved?: false},
               %{ledger: ledger},
               dispatch_mode: :manual,
               max_concurrency: 1,
               hooks: hooks
             )

    step_until_reserved(runner, id, tag, ledger)
    assert :ok = Runic.Runner.stop(runner, id, persist: true)

    assert {:ok, _worker} =
             Jido.Exec.resume(runner, id, %{ledger: ledger},
               dispatch_mode: :manual,
               max_concurrency: 1,
               hooks: hooks
             )

    assert %Runic.Workflow{} = step_to_completion(runner, id, tag)
    assert {:ok, output} = Jido.Exec.result(runner, id)
    assert output.charge.status == :declined
    assert output.settlement.status == :compensated

    state = Agent.get(ledger, & &1)
    assert state.reservations == %{}

    assert state.operations == [
             {:reserve, "reservation:order-1"},
             {:release, "reservation:order-1"}
           ]
  end

  test "confirms a successful reservation", %{ledger: ledger} do
    assert {:ok, output} =
             Jido.Exec.run(
               Jido.Examples.Patterns.Compensation,
               %{order_id: "order-2", amount: 75, approved?: true},
               %{ledger: ledger}
             )

    assert output.charge.status == :approved
    assert output.settlement.status == :confirmed

    assert Agent.get(ledger, & &1.operations) == [
             {:reserve, "reservation:order-2"},
             {:confirm, "reservation:order-2"}
           ]
  end

  defp step_until_reserved(runner, id, tag, ledger) do
    if Agent.get(ledger, &(&1.operations != [])) do
      :ok
    else
      assert {:ok, %Runic.Workflow{}} = Jido.Exec.step(runner, id)
      assert_receive {^tag, :unit_done}, 1_000
      step_until_reserved(runner, id, tag, ledger)
    end
  end

  defp step_to_completion(runner, id, tag) do
    case Jido.Exec.step(runner, id) do
      {:ok, %Runic.Workflow{}} ->
        assert_receive {^tag, :unit_done}, 1_000
        step_to_completion(runner, id, tag)

      {:complete, %Runic.Workflow{} = workflow} ->
        workflow
    end
  end
end
