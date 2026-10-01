Code.require_file("support/fuzz.exs", __DIR__)
Code.require_file("support/report.exs", __DIR__)

defmodule JidoTest.Property.StateTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias JidoTest.Property.Fuzz

  @modes ~w(valid_default invalid_default explicit_nil nullable_nil incomplete_candidate state_history restored_state transform_schema coercion_schema optional_field)
  @cases Enum.map(@modes, &("AGT-002/" <> &1))

  def observe(value, _opts) do
    send(self(), {:state_leaf_checked, value})
    :ok
  end

  def transform(value, _opts) do
    send(self(), :state_transform_called)
    value + 1
  end

  for {suite, runs, time} <- [{:property, 30, 10_000}, {:fuzz, 300, 120_000}] do
    @tag [
      {suite, true},
      {:fuzz_id, "agent_state"},
      {:contracts, ["AGT-002"]},
      {:contract_cases, @cases},
      {:timeout, 180_000}
    ]
    test "#{suite} checked defaults and immutable complete state" do
      generator =
        StreamData.fixed_map(%{
          "mode" => StreamData.member_of(@modes),
          "depth" => StreamData.integer(0..70),
          "value" => StreamData.integer(-100..100),
          "deltas" => StreamData.list_of(StreamData.integer(-5..5), min_length: 1, max_length: 5)
        })

      examples =
        for mode <- @modes,
            depth <- [0, 1, 2, 64, 70],
            do: %{"mode" => mode, "depth" => depth, "value" => 1, "deltas" => [0, 1, -1]}

      Fuzz.check(
        "agent_state",
        generator,
        [
          fuzz: unquote(suite) == :fuzz,
          max_runs: unquote(runs),
          max_run_time: unquote(time),
          max_shrinking_steps: 100,
          timeout: 180_000,
          contracts: ["AGT-002"],
          contract_cases: @cases,
          examples: examples,
          corpus: [Path.join(__DIR__, "corpus/agent_state/nested_invalid.json")]
        ],
        &check_state/1
      )
    end
  end

  defp check_state(%{"mode" => mode, "depth" => depth, "value" => value} = input) do
    leaf =
      case mode do
        "nullable_nil" ->
          Zoi.integer() |> Zoi.nullable() |> Zoi.default(nil)

        "invalid_default" ->
          Zoi.integer() |> Zoi.default("bad")

        "transform_schema" ->
          Zoi.integer() |> Zoi.transform({__MODULE__, :transform, []}) |> Zoi.default(value)

        "coercion_schema" ->
          Zoi.integer(coerce: true) |> Zoi.default(value)

        "optional_field" ->
          Zoi.integer() |> Zoi.default(value) |> Zoi.optional()

        _ ->
          Zoi.integer() |> Zoi.refine({__MODULE__, :observe, []}) |> Zoi.default(value)
      end

    field =
      Enum.reduce(1..depth//1, leaf, fn _, child ->
        Zoi.object(%{child: child}, empty_values: [nil]) |> Zoi.default(%{})
      end)

    result =
      Agent.new(name: "property_state", schema: Zoi.object(%{root: field}, empty_values: [nil]))

    cond do
      mode in ~w(transform_schema coercion_schema) ->
        assert {:error, %Jido.Error.ValidationError{subject: :schema}} = result
        refute_received :state_transform_called

      mode == "invalid_default" ->
        assert {:ok, definition} = result
        assert {:error, %Jido.Error.ValidationError{}} = Agent.instantiate(definition)

      mode == "optional_field" ->
        assert {:ok, definition} = result
        agent = Agent.instantiate!(definition)
        assert agent.state === optional_shape(depth)
        assert Agent.validate_instance(agent) === {:ok, agent}
        assert Agent.transition(agent, agent.state) === {:ok, agent}

      true ->
        assert {:ok, definition} = result

        state =
          case mode do
            "explicit_nil" -> %{root: nest(nil, depth)}
            "nullable_nil" -> %{root: nest(nil, depth)}
            _ -> %{}
          end

        agent = Agent.instantiate!(definition, state: state)
        expected = if mode == "nullable_nil", do: nil, else: value
        assert agent.state === %{root: nest(expected, depth)}

        if mode != "nullable_nil" do
          assert_received {:state_leaf_checked, ^value}
          refute_received {:state_leaf_checked, _}
        end

        case mode do
          "incomplete_candidate" ->
            candidate = if depth == 0, do: %{}, else: %{root: %{}}
            assert {:error, %Jido.Error.ValidationError{}} = Agent.transition(agent, candidate)
            assert agent.state === %{root: nest(value, depth)}

          "restored_state" ->
            assert {:ok, checkpoint} = Agent.checkpoint(agent)
            assert {:ok, ^agent} = Agent.restore(Agent, checkpoint)

            for invalid <- [%{}, %{root: nest(nil, depth)}] do
              assert {:error, %Jido.Error.ValidationError{}} =
                       Agent.restore(Agent, %{checkpoint | state: invalid})
            end

          "state_history" ->
            {_next, _model} =
              Enum.reduce(input["deltas"], {agent, value}, fn delta, {old, model} ->
                next_value = model + delta
                assert {:ok, next} = Agent.transition(old, %{root: nest(next_value, depth)})
                assert old.state === %{root: nest(model, depth)}
                assert next.state === %{root: nest(next_value, depth)}
                assert Agent.validate_instance(next) === {:ok, next}
                {next, next_value}
              end)

          _ ->
            assert Agent.validate_instance(agent) === {:ok, agent}
        end

        flush_checks()
    end

    ["AGT-002/" <> mode]
  end

  defp nest(value, depth), do: Enum.reduce(1..depth//1, value, fn _, child -> %{child: child} end)
  defp optional_shape(0), do: %{}
  defp optional_shape(depth), do: %{root: nest(%{}, depth - 1)}

  defp flush_checks do
    receive do
      {:state_leaf_checked, _} -> flush_checks()
    after
      0 -> :ok
    end
  end
end
