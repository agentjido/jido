Code.require_file("../support/case.exs", __DIR__)
Code.require_file("../support/turn_model.exs", __DIR__)

for adapter <- [:ets, :file, :ecto] do
  defmodule Module.concat(JidoTest.System.TurnSequences, Macro.camelize(to_string(adapter))) do
    use JidoTest.System.Case, async: false
    @moduletag :system
    @moduletag adapter: adapter

    @rounds System.get_env("JIDO_SYSTEM_MODEL_ROUNDS", "2") |> String.to_integer()
    if @rounds not in 1..1_000, do: raise("JIDO_SYSTEM_MODEL_ROUNDS must be in 1..1000")

    @seeds (case System.get_env("JIDO_SYSTEM_MODEL_SEED") do
              nil -> [17, 93, 8_191]
              value -> [String.to_integer(value)]
            end)

    for seed <- @seeds do
      @model_seed seed
      @tag model_seed: seed
      @tag scenario: :burn_in
      @tag timeout: max(120_000, @rounds * 2_000)
      test "mixed Turn sequence agrees with the independent oracle, seed #{@model_seed}", c do
        assert :ok = JidoTest.System.TurnModel.verify(c, @model_seed, @rounds)
      end
    end
  end
end

defmodule JidoTest.System.TurnModelReducerTest do
  use ExUnit.Case, async: true
  @moduletag :system
  alias JidoTest.System.TurnModel

  test "failure reduction replays candidates and retains the minimum failing sequence" do
    commands = [:success, :restart, :delete, :cancel, :restart]

    assert {[:delete, :restart], true} =
             TurnModel.shrink(commands, fn candidate ->
               case Enum.split_while(candidate, &(&1 != :delete)) do
                 {_, [:delete | rest]} -> :restart in rest
                 _ -> false
               end
             end)
  end

  test "failure reduction reports an exhausted replay budget" do
    assert {[:b, :c], false} = TurnModel.shrink([:a, :b, :c], fn _ -> true end, 1)
  end
end
