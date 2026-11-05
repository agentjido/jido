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
    for filename <- ["flow-steps.md", "flow-choices.md", "flow-collections.md", "flow-iterate-state.md"] do
      evaluate_first_block(filename)
    end
  end

  test "the linked Invoke example supports final results and continuations" do
    # The guide block matches both results: a final result and a continuation.
    evaluate_first_block("dynamic-flows.md")
  end

  defp evaluate_first_block(filename) do
    {guide, [source | _blocks]} = guide_blocks(filename)
    modules = ~r/defmodule (\S+) do/ |> Regex.scan(source, capture: :all_but_first) |> List.flatten()
    evaluate_example(source, guide, Enum.map(modules, &Module.concat([&1])))
  end

  defp guide_blocks(filename) do
    guide = Path.expand("../../../../guides/flows/#{filename}", __DIR__)
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
