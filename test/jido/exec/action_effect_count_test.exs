defmodule Jido.Exec.ActionEffectCountTest do
  use ExUnit.Case, async: false

  alias Jido.Joi

  defmodule Effects do
    use Jido.Action, name: "effect_count_effects", schema: Joi.map()

    def run(_params, _context), do: {:ok, %{ok: true}, [:first, :second]}
  end

  defmodule NoEffects do
    use Jido.Action, name: "effect_count_none", schema: Joi.map()

    def run(_params, _context), do: {:ok, %{ok: true}}
  end

  defmodule NestedThenNoEffects do
    use Jido.Action, name: "effect_count_nested", schema: Joi.map()

    def run(_params, _context) do
      {:ok, _output, [_, _]} = Jido.Exec.run(Effects)
      {:ok, %{ok: true}}
    end
  end

  defmodule StepFlow do
    use Jido.Flow, name: "effect_count_step"

    flow do
      step "a", action: Effects, params: %{}
      output result("a")
    end
  end

  defmodule NoEffectsFlow do
    use Jido.Flow, name: "effect_count_no_effects"

    flow do
      step "a", action: NestedThenNoEffects, params: %{}
      output result("a")
    end
  end

  defmodule MapFlow do
    use Jido.Flow, name: "effect_count_map"

    flow do
      map "m", collection: input(:items), action: Effects, params: %{item: item()}
      output %{items: result("m")}
    end
  end

  setup do
    id = "effect-count-#{System.unique_integer([:positive])}"
    :telemetry.attach(id, [:jido, :action, :stop], &__MODULE__.forward/4, self())
    on_exit(fn -> :telemetry.detach(id) end)
  end

  def forward(_event, _measurements, metadata, test_pid) do
    send(test_pid, {:action_stop, metadata.action, metadata.outcome, metadata.effect_count})
  end

  @tag obligation: "jido_action.execution.I19"
  test "a directly run Action counts its effects" do
    assert {:ok, _, [:first, :second]} = Jido.Exec.run(Effects)
    assert_received {:action_stop, Effects, :ok, 2}
  end

  test "a Flow step counts the effects of its Action" do
    assert {:ok, _, [:first, :second]} = Jido.Exec.run(StepFlow)
    assert_received {:action_stop, Effects, :ok, 2}
  end

  test "each Map item counts the effects of its Action" do
    assert {:ok, _, effects} = Jido.Exec.run(MapFlow, %{items: [1, 2]})
    assert length(effects) == 4
    assert_received {:action_stop, Effects, :ok, 2}
    assert_received {:action_stop, Effects, :ok, 2}
  end

  test "an Action without effects does not report those of a nested call" do
    assert {:ok, _} = Jido.Exec.run(NoEffectsFlow)
    assert_received {:action_stop, NestedThenNoEffects, :ok, 0}
  end

  test "a nested Action run leaves no telemetry state in its caller" do
    before = Process.get_keys()
    assert {:ok, _, _} = Jido.Exec.run(Effects)
    assert Process.get_keys() -- before == []
  end
end
