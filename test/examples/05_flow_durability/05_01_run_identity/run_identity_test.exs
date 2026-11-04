Code.require_file("../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Durability.RunIdentityTest do
  use ExUnit.Case, async: false
  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!("05_flow_durability/05_01_run_identity/run_identity.ex")

    :ok
  end

  test "keeps one managed execution identity" do
    runner = Module.concat(__MODULE__, Runner)
    start_supervised!({Runic.Runner, name: runner})
    id = {:run_identity, System.unique_integer([:positive])}
    owner = self()

    hooks = [
      on_dispatch: fn _units, state -> send(owner, {:scope, state.current_execution_id}) end,
      on_idle: fn _state -> send(owner, :idle) end
    ]

    assert {:ok, _worker} =
             Jido.Exec.start(
               runner,
               id,
               Jido.Examples.Durability.RunIdentity,
               %{value: 7},
               %{},
               hooks: hooks
             )

    assert_receive {:scope, scope_id}, 1_000
    assert_receive :idle, 1_000
    assert {:ok, observation} = Runic.Runner.execution(runner, id, scope_id)
    assert observation.quiescent?
    assert observation.id.domain == :execution
    assert observation.input_id.domain == :input_command
    assert observation.input_fact_id.domain == :fact_occurrence
    assert Jido.Exec.result(runner, id) == {:ok, %{value: 7}, [:identified]}
  end
end
