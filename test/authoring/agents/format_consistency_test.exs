Code.require_file("../support/agents/composable_fixtures.exs", __DIR__)
Code.require_file("../support/agents/composable_compiler.exs", __DIR__)

defmodule Jido.Agent.FormatConsistencyTest do
  use ExUnit.Case, async: true
  @moduletag :authoring
  alias Jido.Agent
  alias JidoTest.ComposableAgent.{Action, Flow, Worker, Audit, Compiler}

  defp canonical(fields) do
    struct!(
      Agent,
      Map.merge(
        %{
          id: nil,
          state: nil,
          module: nil,
          name: "formats",
          description: nil,
          vsn: 1,
          schema: Zoi.object(%{}),
          metadata: %{},
          signal_source: nil,
          routes: [],
          topology: %{agents: [], connections: []},
          extensions: []
        },
        fields
      )
    )
  end

  defp route(path, handler, opts \\ []) do
    Map.merge(
      %{path: path, as: nil, defaults: %{}, handler: handler},
      Map.new(opts)
    )
  end

  defp action(path, opts \\ []),
    do: route(path, %{kind: :action, target: Action}, opts)

  test "Map, struct and DSL have exact field equality for independent declarations" do
    cases = [
      {"", %{}},
      {~s(agent do metadata %{label: "formats"} end),
       %{description: "example", vsn: 3, metadata: %{label: "formats"}}},
      {~s"agent do schema Zoi.object(%{flag: Zoi.boolean() |> Zoi.default(false), count: Zoi.integer() |> Zoi.default(0)}) end",
       %{
         schema:
           Zoi.object(%{
             flag: Zoi.boolean() |> Zoi.default(false),
             count: Zoi.integer() |> Zoi.default(0)
           })
       }},
      {~s(routes do signal_source "/formats"; route "work.request", #{inspect(Action)}, as: :work; route "work.*", #{inspect(Action)} end),
       %{
         signal_source: "/formats",
         routes: [action("work.request", as: :work), action("work.*")]
       }},
      {"routes do route \"work.request\", #{inspect(Action)}, defaults: %{value: \"fallback\"}; route \"plan.request\", #{inspect(Flow)} end",
       %{
         routes: [
           action("work.request", defaults: %{value: "fallback"}),
           route("plan.request", %{kind: :flow, target: Flow})
         ]
       }},
      {"topology do agent :worker, #{inspect(Worker)}, count: 2, initial_state: %{value: \"copied\"} end",
       %{
         topology: %{
           agents: [
             %{name: :worker, definition: Worker, count: 2, initial_state: %{value: "copied"}}
           ],
           connections: []
         }
       }},
      {"agent do plugin #{inspect(Audit)}, config: %{label: \"formats\", enabled: false} end",
       %{
         extensions: [
           %{id: Audit.id(), provider: Audit, vsn: 1, data: %{label: "formats", enabled: false}}
         ]
       }}
    ]

    for {body, fields} <- cases do
      opts =
        ~s(name: "formats") <>
          if(Map.has_key?(fields, :description),
            do: ~s(, description: "example", vsn: 3),
            else: ""
          )

      module = Compiler.compile(body, opts)
      fields = Map.put(fields, :module, module)
      expected = canonical(fields)
      raw_map = Map.merge(%{name: "formats"}, fields)
      raw_struct = canonical(raw_map)

      assert module.definition() === expected
      assert Agent.define!(raw_map) === expected
      assert Agent.define!(raw_struct) === expected
      assert Agent.define!(expected) === expected

      for source <- [Agent.define!(raw_map), Agent.define!(raw_struct), module] do
        instance = Agent.instantiate!(source, id: "formats-1")
        assert Agent.definition(instance) === expected
        assert instance.id == "formats-1"
        assert Agent.validate(instance) == {:ok, instance}
      end
    end
  end

  test "three forms preserve nil, false, zero and nested state defaults without coercion" do
    module =
      Compiler.compile(
        """
        agent do
          schema Zoi.object(%{
            flag: Zoi.boolean() |> Zoi.default(false),
            count: Zoi.integer() |> Zoi.default(0),
            label: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
            nested: Zoi.object(%{value: Zoi.string() |> Zoi.default("default")}) |> Zoi.default(%{})
          })
        end
        """,
        ~s(name: "formats")
      )

    fields = %{
      name: "formats",
      module: module,
      schema:
        Zoi.object(%{
          flag: Zoi.boolean() |> Zoi.default(false),
          count: Zoi.integer() |> Zoi.default(0),
          label: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
          nested: Zoi.object(%{value: Zoi.string() |> Zoi.default("default")}) |> Zoi.default(%{})
        })
    }

    for source <- [Agent.define!(fields), canonical(fields), module] do
      assert Agent.define!(if(is_atom(source), do: source.definition(), else: source)) ===
               canonical(fields)

      instance = Agent.instantiate!(source, id: "one", state: %{nested: %{value: "given"}})
      assert instance.state === %{flag: false, count: 0, label: nil, nested: %{value: "given"}}
      assert {:error, _} = Agent.instantiate(source, id: "bad", state: %{count: "0"})
      assert {:error, _} = Agent.validate(%{instance | state: %{count: 0}})
    end
  end

  test "Map and struct report the same error path and DSL rejects the same declaration" do
    cases = [
      {%{routes: [action("work.request"), action("work.request")]},
       ~s(routes do route "work.request", #{inspect(Action)}; route "work.request", #{inspect(Action)} end)},
      {%{routes: [action("one", as: :same), action("two", as: :same)], signal_source: "/test"},
       ~s(routes do signal_source "/test"; route "one", #{inspect(Action)}, as: :same; route "two", #{inspect(Action)}, as: :same end)},
      {%{topology: %{agents: [%{name: :worker, definition: Worker, count: 0}], connections: []}},
       "topology do agent :worker, #{inspect(Worker)}, count: 0 end"}
    ]

    for {fields, body} <- cases do
      input = Map.put(fields, :name, "formats")
      assert {:error, map_error} = Agent.define(input)
      assert {:error, struct_error} = Agent.define(canonical(input))
      assert map_error === struct_error
      assert map_error.path != []

      error =
        try do
          Compiler.compile(body, ~s(name: "formats"))
          flunk("DSL accepted an invalid declaration")
        rescue
          error in [Agent.Error, Spark.Error.DslError] -> error
        end

      assert Exception.message(error) =~ map_error.message
    end
  end
end
