defmodule Jido.Flow.DSL.SparkSurfaceTest do
  use ExUnit.Case, async: false

  test "every public declaration has a schema-derived field reference" do
    [section] = Jido.Flow.DSL.Extension.sections()
    {:docs_v1, _, _, _, %{"en" => docs}, _, _} = Code.fetch_docs(Jido.Flow)
    assert docs =~ "## DSL field reference"
    assert docs =~ "Flow can contain more than one Invoke"
    refute docs =~ "__source__"

    entities =
      Enum.flat_map(
        section.entities,
        &[&1 | Enum.flat_map(&1.entities, fn {_, children} -> children end)]
      )

    assert length(entities) == 18

    for entity <- entities do
      schema = Keyword.delete(entity.schema, :__source__)
      name = entity.name |> to_string() |> String.trim("_") |> String.capitalize()
      assert docs =~ "# #{name}\n"
      assert docs =~ Spark.Options.docs(schema)
      refute docs =~ to_string(entity.name)

      for {field, options} <- schema do
        assert is_binary(options[:doc]) and options[:doc] != "",
               "missing docs for #{entity.name}.#{field}"
      end
    end

    for guide <- [
          "flow-steps",
          "flow-choices",
          "flow-collections",
          "flow-iterate-state",
          "dynamic-flows"
        ] do
      assert docs =~ "#{guide}.html"
    end
  end

  test "the linked guide examples compile, run, and format consistently" do
    for {filename, indexes, modules, expected} <- [
          {"flow-collections.livemd", [1, 2, 3], [FlowCollections.Double, FlowCollections.Sum, FlowCollections.Example],
           %{
             items: [%{value: 2, index: 0}, %{value: 4, index: 1}, %{value: 6, index: 2}],
             total: %{total: 12}
           }},
          {"flow-choices.livemd", [1, 2, 3], [FlowChoices.Route, FlowChoices.Example],
           {%{route: %{queue: :urgent, id: 1}}, %{route: %{queue: :standard, id: 2}}}},
          {"flow-iterate-state.livemd", [1, 2, 3], [FlowIterate.Increment, FlowIterate.RepeatThree],
           {:ok,
            %{
              counter: %{
                kind: :jido_flow_iterate_result,
                iterations: 3,
                state: %{count: 3},
                output: %{count: 3, index: 2}
              }
            }}},
          {"flow-steps.livemd", [2, 3, 4], [FlowSteps.Echo, FlowSteps.Example],
           %{first: %{value: 7}, second: %{value: 7, tag: :complete}}}
        ] do
      {guide, blocks} = guide_blocks(filename)
      source = Enum.map_join(indexes, "\n", &Enum.fetch!(blocks, &1))
      assert evaluate_example(source, guide, modules) == expected, filename
    end
  end

  test "the linked Invoke example supports final results and continuations" do
    {guide, blocks} = guide_blocks("dynamic-flows.md")

    evaluate_example(Enum.fetch!(blocks, 1), guide, [
      MyApp.Actions.ChooseRoute,
      MyApp.Actions.ExpandRoute,
      MyApp.Flows.DynamicRoute
    ])

    inline = apply(MyApp.Flows.DynamicRoute, :step_action, ["prepare"])

    on_exit(fn ->
      :code.purge(inline)
      :code.delete(inline)
    end)

    for mode <- [:finish, :continue] do
      assert Jido.Exec.run(MyApp.Flows.DynamicRoute, %{
               mode: mode,
               value: 3,
               target: Jido.Test.Action.Fixtures.Actions.EchoParamsAction
             }) == {:ok, %{value: 3}}
    end
  end

  defp guide_blocks(filename) do
    guide = Path.expand("../../../../guides/#{filename}", __DIR__)
    blocks = Regex.scan(~r/```elixir\n(.*?)\n```/s, File.read!(guide), capture: :all_but_first)
    {guide, List.flatten(blocks)}
  end

  defp evaluate_example(source, guide, modules) do
    on_exit(fn ->
      for module <- modules do
        :code.purge(module)
        :code.delete(module)
      end
    end)

    {formatter, _} = Mix.Tasks.Format.formatter_for_file("guide_example.ex")
    formatted = formatter.(source)
    assert formatter.(formatted) == formatted
    {result, _bindings} = Code.eval_string(formatted, [], file: guide)

    result
  end
end
