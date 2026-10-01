Code.require_file("support/fuzz.exs", __DIR__)
Code.require_file("support/report.exs", __DIR__)

defmodule JidoTest.Property.EffectsTraceContractTest do
  use JidoTest.Case, async: false
  alias JidoTest.Property.Fuzz
  alias Jido.Tracing.{Context, Trace}

  defmodule Effect do
    use Jido.Agent.Directive
    defstruct [:value]
    def validate(%__MODULE__{value: value} = effect) when is_integer(value), do: {:ok, effect}
    def validate(_), do: {:error, Jido.Error.validation_error("invalid effect")}
  end

  defmodule Plugin do
    use Jido.Plugin
    def directives(_), do: [Effect]

    def dispatch(_, %Effect{value: value}, context, _) do
      server = Jido.whereis_agent(context.jido, context.agent_id)
      send(context.turn_context.observer, {:effect, value, Jido.AgentServer.snapshot(server)})
      if value == context.turn_context.fail_at, do: {:error, :effect_refused}, else: :ok
    end
  end

  defmodule Produce do
    use Jido.Action, name: "property_produce_effects"

    def run(%{values: values}, _context) do
      {:ok, %{count: Enum.sum(values)}, Enum.map(values, &%Effect{value: &1})}
    end
  end

  for suite <- [:property, :fuzz] do
    @tag [
      {suite, true},
      fuzz_id: "effect_order",
      contracts: ["EFFECT-001"],
      contract_cases: ["EFFECT-001/ordered", "EFFECT-001/failed-tail"]
    ]
    @tag timeout: 180_000
    test "#{suite}: effects follow the committed state and stop after failure", ctx do
      gen =
        StreamData.fixed_map(%{
          "values" => StreamData.list_of(StreamData.integer(1..30), min_length: 1, max_length: 5),
          "fail" => StreamData.boolean()
        })

      opts = options(unquote(suite), "EFFECT-001", ["ordered", "failed-tail"])

      Fuzz.check(
        "effect_order",
        gen,
        opts ++
          [
            examples: [
              %{"values" => [2, 3], "fail" => false},
              %{"values" => [2, 3], "fail" => true}
            ]
          ],
        fn input ->
          values = input["values"]
          expected = %{count: Enum.sum(values)}

          agent =
            Jido.Agent.new!(
              name: "effect_property",
              schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
              routes: [{"property.effects", Produce}],
              plugins: [Plugin]
            )
            |> Jido.Agent.instantiate!()

          signal = signal("property.effects", %{values: values})
          assert {:ok, direct, effects} = Jido.Agent.cmd(agent, signal)
          assert direct.state === expected
          assert Enum.map(effects, & &1.value) === values
          refute_received {:effect, _, _}
          {:ok, server} = Jido.start_agent(ctx.jido, agent)
          monitor = Process.monitor(server)

          try do
            fail_at = if input["fail"], do: hd(values), else: nil

            assert {:ok, committed} =
                     Jido.AgentServer.call(server, signal,
                       context: %{observer: self(), fail_at: fail_at}
                     )

            # A snapshot call is an admitted event after the internal effect batch.
            assert Jido.AgentServer.snapshot(server) === %{agent: committed, state_version: 1}
            observed = if input["fail"], do: [hd(values)], else: values

            for value <- observed do
              assert_receive {:effect, ^value, snapshot}, 1_000
              assert snapshot.agent.state === expected
              assert snapshot.state_version === 1
            end

            refute_received {:effect, _, _}
            assert committed.state === expected
            [if(input["fail"], do: "failed-tail", else: "ordered")]
          after
            Jido.stop_agent(ctx.jido, server)
            assert_receive {:DOWN, ^monitor, :process, ^server, _}, 1_000
          end
        end
      )
    end

    @tag [
      {suite, true},
      fuzz_id: "trace_context",
      contracts: ["TRACE-001"],
      contract_cases: ["TRACE-001/carrier", "TRACE-001/restore"]
    ]
    @tag timeout: 180_000
    test "#{suite}: carrier fields and previous context survive success and failure" do
      gen =
        StreamData.fixed_map(%{
          "cause" => StreamData.string(:alphanumeric, min_length: 1, max_length: 20),
          "failure" => StreamData.boolean()
        })

      opts = options(unquote(suite), "TRACE-001", ["carrier", "restore"])

      Fuzz.check(
        "trace_context",
        gen,
        opts ++
          [
            examples: [
              %{"cause" => "fixed-source", "failure" => false},
              %{"cause" => "fixed-source", "failure" => true}
            ]
          ],
        fn input ->
          trace_id = "0123456789abcdef0123456789abcdef"
          span_id = "0123456789abcdef"

          carrier = %{
            trace_id: trace_id,
            span_id: span_id,
            trace_flags: "01",
            traceparent: "00-#{trace_id}-#{span_id}-01"
          }

          previous = %{sentinel: input["cause"]}
          Context.put(previous)

          try do
            operation = fn ->
              assert Context.get() === carrier

              assert {:ok, propagated} =
                       Context.propagate_to(signal("property.trace"), input["cause"])

              expected = Map.put(carrier, :causation_id, input["cause"])
              assert Trace.get(propagated) === expected
              child = Context.begin_turn(propagated)
              assert child.trace_id === trace_id
              assert child.parent_span_id === span_id
              assert child.causation_id === input["cause"]
              refute child.span_id === span_id
              if input["failure"], do: throw(:forced_failure), else: :ok
            end

            if input["failure"],
              do:
                assert(catch_throw(Context.with_context(carrier, operation)) === :forced_failure),
              else: assert(Context.with_context(carrier, operation) === :ok)

            assert Context.get() === previous
            ["carrier", "restore"]
          after
            Context.clear()
          end
        end
      )
    end
  end

  defp options(suite, contract, cases) do
    [
      fuzz: suite == :fuzz,
      contracts: [contract],
      contract_cases: Enum.map(cases, &(contract <> "/" <> &1)),
      max_runs: if(suite == :fuzz, do: 300, else: 30),
      max_run_time: if(suite == :fuzz, do: 120_000, else: 10_000),
      max_shrinking_steps: 100,
      timeout: 180_000
    ]
  end
end
