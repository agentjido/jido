defmodule Jido.Agent.Turn.OutcomeTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Turn.Outcome
  alias Jido.Signal
  alias Jido.Signal.ID

  test "schema, map, keyword, struct, and raising constructors agree" do
    assert %Zoi.Types.Struct{module: Outcome} = Outcome.schema()
    attrs = attrs()

    assert {:ok, %Outcome{} = outcome} = Outcome.new(attrs)
    assert {:ok, ^outcome} = Outcome.new(Map.to_list(attrs))
    assert {:ok, ^outcome} = Outcome.new(outcome)
    assert Outcome.new!(attrs) == outcome

    assert {:error, %Jido.Error.ValidationError{}} = apply(Outcome, :new, [:invalid])

    assert_raise Jido.Error.ValidationError, fn ->
      Outcome.new!(%{attrs | id: "not-a-turn-id"})
    end
  end

  test "accepts all valid terminal status and stage combinations" do
    for status <- [:failed, :cancelled, :timed_out, :indeterminate],
        stage <- [:prepare, :execute, :finalize, :commit] do
      assert {:ok, %Outcome{status: ^status, stage: ^stage, committed?: false}} =
               Outcome.new(attrs(status: status, stage: stage))
    end

    for stage <- [:commit, :directive] do
      assert {:ok, %Outcome{status: :succeeded, stage: ^stage, committed?: true}} =
               Outcome.new(
                 attrs(
                   status: :succeeded,
                   stage: stage,
                   committed?: true,
                   state_version_after: 4,
                   error: nil
                 )
               )
    end

    assert {:ok, %Outcome{status: :failed, stage: :directive, committed?: true}} =
             Outcome.new(
               attrs(
                 stage: :directive,
                 committed?: true,
                 state_version_after: 4,
                 directives: summary(3, 1, 1, 1, 1)
               )
             )
  end

  test "rejects inconsistent status, stage, and state version fields" do
    invalid = [
      attrs(status: :succeeded, error: :failure),
      attrs(status: :succeeded, stage: :commit, error: nil),
      attrs(stage: :directive),
      attrs(committed?: true, state_version_after: 3),
      attrs(committed?: true, state_version_after: 5),
      attrs(state_version_after: 4),
      attrs(
        status: :succeeded,
        stage: :prepare,
        committed?: true,
        state_version_after: 4,
        error: nil
      )
    ]

    for attrs <- invalid do
      assert {:error, %Jido.Error.ValidationError{}} = Outcome.new(attrs)
    end
  end

  test "validates every Directive count and failed index rule" do
    for directives <- [
          summary(2, 2, 0, nil, 0),
          summary(3, 1, 1, 1, 1),
          summary(3, 0, 1, 0, 2)
        ] do
      assert {:ok, %Outcome{directives: ^directives}} = Outcome.new(attrs(directives: directives))
    end

    for directives <- [
          summary(2, 1, 0, nil, 0),
          summary(2, 1, 1, nil, 0),
          summary(2, 1, 1, 0, 0),
          summary(2, 0, 2, 0, 0),
          summary(0, 0, 0, 0, 0)
        ] do
      assert {:error, %Jido.Error.ValidationError{}} = Outcome.new(attrs(directives: directives))
    end
  end

  test "requires ordered timestamps and a non-negative measured duration" do
    assert {:ok, %Outcome{duration_ms: 5}} = Outcome.new(attrs())
    assert {:ok, %Outcome{duration_ms: 4}} = Outcome.new(attrs(duration_ms: 4))

    for changes <- [[finished_at: 4], [duration_ms: -1], [started_at: 11, finished_at: 10]] do
      assert {:error, _reason} = Outcome.new(attrs(changes))
    end
  end

  defp attrs(overrides \\ []) do
    signal = Signal.new!("counter.add", %{by: 1}, source: "/test")

    Map.merge(
      %{
        id: ID.generate!(),
        agent_id: "counter-1",
        source_signal: signal,
        effective_signal: signal,
        status: :failed,
        stage: :execute,
        committed?: false,
        state_version_before: 3,
        state_version_after: nil,
        error: :simulated_failure,
        directives: summary(0, 0, 0, nil, 0),
        started_at: 5,
        finished_at: 10,
        duration_ms: 5
      },
      Map.new(overrides)
    )
  end

  defp summary(total, completed, failed, failed_index, skipped) do
    %{
      total: total,
      completed: completed,
      failed: failed,
      failed_index: failed_index,
      skipped: skipped
    }
  end
end
