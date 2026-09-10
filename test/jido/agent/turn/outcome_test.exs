defmodule Jido.Agent.Turn.OutcomeTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Turn.Outcome
  alias Jido.AgentServer.ActiveTurn
  alias Jido.Signal
  alias Jido.Signal.ID

  test "ActiveTurn produces the terminal Outcome record" do
    signal = Signal.new!("counter.add", %{by: 1}, source: "/test")
    active = ActiveTurn.new(signal, nil, 3)
    outcome = ActiveTurn.outcome(active, "counter-1", :failed, :execute, :failure)

    assert %Outcome{
             id: id,
             agent_id: "counter-1",
             source_signal: ^signal,
             effective_signal: nil,
             status: :failed,
             stage: :execute,
             committed?: false,
             state_version_before: 3,
             state_version_after: nil,
             error: :failure,
             directives: %{
               total: 0,
               completed: 0,
               failed: 0,
               failed_index: nil,
               skipped: 0
             },
             started_at: started_at,
             finished_at: finished_at,
             duration_ms: duration_ms
           } = outcome

    assert ID.valid?(id)
    assert finished_at >= started_at
    assert duration_ms >= 0
  end

  test "ActiveTurn records commit and Directive completion" do
    signal = Signal.new!("counter.add", %{}, source: "/test")

    outcome =
      signal
      |> ActiveTurn.new(nil, 8)
      |> ActiveTurn.mark_committed(9, 3)
      |> ActiveTurn.mark_directive_completed()
      |> ActiveTurn.mark_directive_failed()
      |> ActiveTurn.outcome("counter-1", :failed, :directive, :dispatch_failed)

    assert %Outcome{
             committed?: true,
             state_version_before: 8,
             state_version_after: 9,
             directives: %{
               total: 3,
               completed: 1,
               failed: 1,
               failed_index: 1,
               skipped: 1
             }
           } = outcome
  end

  test "Outcome has no public authoring API" do
    refute function_exported?(Outcome, :schema, 0)
    refute function_exported?(Outcome, :new, 1)
    refute function_exported?(Outcome, :new!, 1)
  end
end
