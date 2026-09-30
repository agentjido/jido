defmodule JidoTest.Property.IntersectionTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Jido.Agent

  @modes [:provided, :defaults, :overlap, :conflict, :missing, :nullable]

  def observe(value, label, _opts) do
    send(self(), {:intersection_leaf, label, value})
    :ok
  end

  for {suite, runs} <- [{:property, 100}, {:fuzz, 1_000}] do
    @tag [{suite, true}, {:timeout, 180_000}]
    test "#{suite} intersection state contracts" do
      Process.put({__MODULE__, :inputs}, 0)

      generator =
        StreamData.fixed_map(%{
          mode: StreamData.member_of(@modes),
          reverse?: StreamData.boolean(),
          depth: StreamData.integer(0..8),
          value: StreamData.integer(-100..100)
        })

      for mode <- @modes, reverse? <- [false, true], depth <- [0, 1, 8] do
        check_case(%{mode: mode, reverse?: reverse?, depth: depth, value: 1})
      end

      check all(
              input <- generator,
              max_runs: unquote(runs),
              max_run_time: 120_000,
              initial_seed: 389
            ) do
        check_case(input)
      end

      assert Process.get({__MODULE__, :inputs}) == unquote(runs) + 36
      IO.puts("Intersection #{unquote(suite)}: #{unquote(runs) + 36} inputs passed")
    end
  end

  defp check_case(%{mode: mode, reverse?: reverse?, depth: depth, value: value}) do
    a = if mode == :nullable, do: nil, else: value
    a_schema = if mode == :nullable, do: Zoi.integer() |> Zoi.nullable(), else: Zoi.integer()
    left = Zoi.object(%{a: leaf(a_schema, a, :left_a)})
    right_fields = %{b: leaf(Zoi.integer(), value + 1, :right_b)}

    right_fields =
      case mode do
        :overlap -> Map.put(right_fields, :a, leaf(Zoi.integer(), value, :right_a))
        :conflict -> Map.put(right_fields, :a, leaf(Zoi.integer(), value + 1, :right_a))
        _ -> right_fields
      end

    branches = [left, Zoi.object(right_fields)]
    branches = if reverse?, do: Enum.reverse(branches), else: branches

    field =
      Enum.reduce(1..depth//1, Zoi.default(Zoi.intersection(branches), %{}), fn _, inner ->
        Zoi.object(%{child: inner}) |> Zoi.default(%{})
      end)

    definition =
      Agent.new!(
        name: "generated_intersection",
        schema: Zoi.object(%{root: field})
      )

    expected = %{root: nest(%{a: a, b: value + 1}, depth)}
    initial = if mode in [:provided, :nullable], do: expected, else: %{}
    result = Agent.instantiate(definition, state: initial)
    labels = collect_checks([]) |> Enum.frequencies()
    expected_labels = %{left_a: 1, right_b: 1}

    expected_labels =
      if mode in [:overlap, :conflict],
        do: Map.put(expected_labels, :right_a, 1),
        else: expected_labels

    assert labels === expected_labels,
           "mode=#{mode} reverse=#{reverse?} depth=#{depth} result=#{inspect(result)}"

    if mode == :conflict do
      assert {:error, %Jido.Error.ValidationError{details: %{errors: errors}}} = result
      path = [:root] ++ List.duplicate(:child, depth) ++ [:a]
      assert Enum.any?(errors, &(&1.path == path))
    else
      assert {:ok, agent} = result
      assert agent.state === expected
      assert Agent.validate_instance(agent) === {:ok, agent}
      assert {:ok, checkpoint} = Agent.checkpoint(agent)
      assert Agent.restore(Agent, checkpoint) === {:ok, agent}

      if mode == :missing do
        incomplete = %{root: nest(%{a: a}, depth)}
        assert {:error, %Jido.Error.ValidationError{}} = Agent.transition(agent, incomplete)

        assert {:error, %Jido.Error.ValidationError{}} =
                 Agent.restore(Agent, %{checkpoint | state: incomplete})

        assert agent.state === expected
      else
        candidate = %{root: nest(%{a: a, b: value + 2}, depth)}
        assert {:ok, next} = Agent.transition(agent, candidate)
        assert next.state === candidate
      end

      collect_checks([])
    end

    Process.put({__MODULE__, :inputs}, Process.get({__MODULE__, :inputs}, 0) + 1)
  end

  defp leaf(schema, default, label),
    do: schema |> Zoi.refine({__MODULE__, :observe, [label]}) |> Zoi.default(default)

  defp nest(value, depth), do: Enum.reduce(1..depth//1, value, fn _, inner -> %{child: inner} end)

  defp collect_checks(labels) do
    receive do
      {:intersection_leaf, label, _value} -> collect_checks([label | labels])
    after
      0 -> labels
    end
  end
end
