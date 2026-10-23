Code.require_file("support/fuzz.exs", __DIR__)
Code.require_file("support/report.exs", __DIR__)
Code.require_file("support/authoring.exs", __DIR__)

defmodule JidoTest.Property.AuthoringContractTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias JidoTest.Property.{Authoring, Fuzz}

  @cases ~w(AGT-001/dsl-neutral AGT-001/inline-history AGT-001/fixture-cleanup)

  # Compilation is part of every attempt. These budgets cover core Agent DSL
  # authoring and inline Action integration, not all external DSL extensions.
  for {suite, runs, time} <- [{:property, 10, 30_000}, {:fuzz, 50, 120_000}] do
    @tag [
      {suite, true},
      {:fuzz_id, "agent_authored_history"},
      {:contracts, ["AGT-001"]},
      {:contract_cases, @cases},
      {:timeout, 180_000}
    ]
    test "#{suite} authored definition and inline command history" do
      generator =
        StreamData.fixed_map(%{
          "initial" => StreamData.integer(-100..100),
          "history" => StreamData.list_of(StreamData.integer(-5..5), max_length: 5)
        })

      examples = [
        %{"initial" => 0, "history" => []},
        %{"initial" => 7, "history" => [0, 1, -1]}
      ]

      replay =
        Path.join(
          System.tmp_dir!(),
          "jido-authored-#{System.pid()}-#{System.unique_integer([:positive])}.json"
        )

      File.write!(
        replay,
        JSON.encode!(%{format: 1, property: "agent_authored_history", input: hd(examples)})
      )

      try do
        Fuzz.check(
          "agent_authored_history",
          generator,
          [
            fuzz: unquote(suite) == :fuzz,
            max_runs: unquote(runs),
            max_run_time: unquote(time),
            max_shrinking_steps: 20,
            timeout: 180_000,
            contracts: ["AGT-001"],
            contract_cases: @cases,
            examples: examples,
            corpus: [replay]
          ],
          &authored_case/1
        )
      after
        File.rm!(replay)
      end
    end
  end

  defp authored_case(input) do
    # Only this local counter can select a module name. Replay data supplies
    # integers and history; it cannot select or replace a module namespace.
    module = Module.concat(__MODULE__, "Fixture#{System.unique_integer([:positive])}")

    source = """
    defmodule #{inspect(module)} do
      use Jido.Agent, name: "property_authored_history"
      state do
        schema Zoi.object(%{value: Zoi.integer(), history: Zoi.list(Zoi.integer())})
      end
      routes do
        signal_source "/property-authored"
        route "property.authored.add", as: :add do
          action %{delta: delta},
            name: "property_authored_add",
            schema: Zoi.object(%{delta: Zoi.integer()}),
            output_schema: Zoi.map(),
            context: context do
            {:ok, %{value: context.agent_state.value + delta,
                    history: context.agent_state.history ++ [delta]}}
          end

          state from: output()
        end
      end
    end
    """

    owned =
      Authoring.with_compiled(
        source,
        fn compiled ->
          inline =
            for {candidate, _} <- :code.all_loaded(),
                function_exported?(candidate, :__jido_inline_action__, 0),
                match?({^module, _}, candidate.__jido_inline_action__()) do
              candidate
            end

          assert [target] = inline
          assert apply(module, :route_executable!, ["property.authored.add"]) == target

          declaration =
            Agent.define!(%{
              module: module,
              name: "property_authored_history",
              signal_source: "/property-authored",
              vsn: 1,
              schema: Zoi.object(%{value: Zoi.integer(), history: Zoi.list(Zoi.integer())}),
              routes: [
                %{
                  path: "property.authored.add",
                  as: :add,
                  handler: %{kind: :action, target: target},
                  state: %{source: :output, path: []}
                }
              ]
            })

          definition = apply(module, :definition, [])
          assert definition === declaration
          assert definition.id == nil and definition.state == nil
          registry = JidoTest.AgentRegistry.for(definition)
          assert {:ok, document} = JidoTest.AgentRegistry.encode(definition, registry)
          assert {:ok, ^document} = JidoTest.AgentRegistry.encode(declaration, registry)

          assert {:ok, ^definition} =
                   JidoTest.AgentRegistry.decode(JSON.decode!(JSON.encode!(document)), registry)

          original =
            apply(module, :instantiate!, [
              [id: "authored", state: %{value: input["initial"], history: []}]
            ])

          assert Agent.definition(original) === declaration
          assert {:ok, encoded_instance} = JidoTest.AgentRegistry.encode(original, registry)
          assert encoded_instance == document
          assert {:ok, ^definition} = JidoTest.AgentRegistry.decode(encoded_instance, registry)

          {current, _model, _history} =
            Enum.reduce(input["history"], {original, input["initial"], []}, fn delta,
                                                                               {agent, model,
                                                                                history} ->
              assert {:ok, signal} = apply(module, :add_signal, [%{delta: delta}])
              assert {:ok, next, []} = Agent.cmd(agent, signal)
              expected_value = model + delta
              expected_history = history ++ [delta]
              assert next.state == %{value: expected_value, history: expected_history}
              assert agent.state == %{value: model, history: history}
              assert Agent.definition(next) === declaration
              {next, expected_value, expected_history}
            end)

          assert {:ok, invalid} = apply(module, :add_signal, [%{delta: "invalid"}])
          assert {:error, error} = Agent.cmd(current, invalid)
          assert is_exception(error)
          assert original.state == %{value: input["initial"], history: []}

          assert current.state == %{
                   value: input["initial"] + Enum.sum(input["history"]),
                   history: input["history"]
                 }

          Enum.uniq(compiled ++ inline)
        end,
        modules: [module]
      )

    for compiled <- owned do
      assert :code.is_loaded(compiled) == false
      refute :erlang.check_old_code(compiled)
    end

    @cases
  end
end
