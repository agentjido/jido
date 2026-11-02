defmodule Jido.Flow.DSL.FormatterTest do
  use ExUnit.Case, async: true

  @package_root Path.expand("../../../..", __DIR__)
  @formatter_path Path.join(@package_root, ".formatter.exs")

  @keyword_flow """
  defmodule FeedbackFlow do
    use Jido.Flow, name: "feedback"

    flow do
      step "validate",
        action: Jido.Examples.FeedbackSummarizer.ValidateBatch,
        params: %{comments: input(:comments), summarizer: input(:summarizer)},
        needs: ["start"]

      map "clean",
        collection: result("validate", :comments),
        action: Jido.Examples.FeedbackSummarizer.CleanComment,
        params: %{comment: item()}

      reduce "combined",
        collection: result("clean"),
        initial: %{},
        action: Merge,
        params: accumulator()

      invoke "next", decision: Decide, expander: Expand, params: result("combined")
      output result("next")
    end
  end
  """

  @block_flow """
  flow do
    step "load" do
      action Load
      params %{value: input(:value), context: context()}
      meta %{owner: "example"}
    end

    choice "route" do
      needs ["prepare"]

      option "match", condition: input(:kind) == :match, action: Match, params: %{}

      option "other" do
        condition input(:kind) == :other
        action Other
        params %{}
      end

      otherwise action: Default, params: %{}
    end

    map "items" do
      collection input(:items)
      action Clean
      params %{item: item(:value)}
      on_error :collect_errors
    end

    iterate "loop" do
      state Zoi.map(), initial: %{count: 0}
      action Increment
      params %{count: state(:count)}
      update %{count: body_result(:count)}
      while state(:count) < 3
      max_iterations 3
    end

    iterate "fixed" do
      state Zoi.map() do
        initial %{count: 0}
      end

      action Increment
      params state()
      repeat 3
    end

    invoke "next" do
      decision Decide
      expander Expand
      params result("fixed")
    end

    output result("next")
  end
  """

  @inline_flow """
  flow do
    step "one", name <- input(:name) do
      {:ok, %{name: String.trim(name)}}
    end

    step "two", [name <- result("one", :name), prefix <- context(:prefix)] do
      {:ok, %{message: prefix <> name}}
    end

    step "two_options", [name <- input(:name), prefix <- context(:prefix)], needs: ["one"] do
      {:ok, %{message: prefix <> name}}
    end

    step "list", [a <- input(:a), b <- input(:b), c <- input(:c)], needs: ["two"] do
      {:ok, %{total: a + b + c}}
    end

    step "pattern", %{name: name} <- input(), meta: %{owner: "example"} do
      {:ok, %{name: name}}
    end

    step "empty", [], needs: ["pattern"], meta: %{owner: "example"} do
      {:ok, %{ready: true}}
    end
  end
  """

  @handoff_flow """
  flow do
    handoff "next", selector: Select, params: input()
    output result("next")
  end
  """

  @inline_keyword_flow """
  step "one", name <- input(:name), do: {:ok, %{name: name}}
  step "two", [a <- input(:a), b <- input(:b)], do: {:ok, %{sum: a + b}}
  step "list", [a <- input(:a), b <- input(:b), c <- input(:c)], do: {:ok, %{sum: a + b + c}}
  step "empty", [], do: {:ok, %{ready: true}}
  """

  @configured_inline_steps """
  flow do
    step "named", name <- input(:name) do
      {:ok, %{name: String.trim(name)}}
    end

    step "configured", [value <- input(:value), offset <- context(:offset)],
      inline: [
        name: "configured",
        schema: Zoi.object(%{value: Zoi.integer(), offset: Zoi.integer()}),
        output_schema: Zoi.object(%{value: Zoi.integer()}),
        context: ctx
      ] do
      {:ok, %{value: value + offset + ctx.extra}}
    end

    step "empty", [], do: {:ok, %{}}

    output result("configured")
  end
  """

  test "the project formatter preserves keyword and block declarations without parentheses" do
    {formatter, _opts} =
      Mix.Tasks.Format.formatter_for_file("flow.ex", dot_formatter: @formatter_path)

    for source <- [
          @keyword_flow,
          @block_flow,
          @handoff_flow,
          @inline_flow,
          @inline_keyword_flow,
          @configured_inline_steps
        ] do
      assert formatter.(source) == source
      assert formatter.(formatter.(source)) == source
    end
  end

  @tag :tmp_dir
  test "a consumer imports the same rules from jido_action", %{tmp_dir: tmp_dir} do
    consumer_formatter = Path.join(tmp_dir, ".formatter.exs")
    File.write!(consumer_formatter, "[import_deps: [:jido]]\n")

    {formatter, _opts} =
      Mix.Tasks.Format.formatter_for_file("flow.ex",
        dot_formatter: consumer_formatter,
        deps_paths: %{jido: @package_root}
      )

    for source <- [
          @keyword_flow,
          @block_flow,
          @handoff_flow,
          @inline_flow,
          @inline_keyword_flow,
          @configured_inline_steps
        ] do
      assert formatter.(source) == source
      assert formatter.(formatter.(source)) == source
    end
  end

  test "the Hex package includes the exported formatter configuration" do
    assert ".formatter.exs" in Mix.Project.config()[:package][:files]
  end

  test "reference calls and explicit parentheses stay unchanged" do
    {formatter, _opts} =
      Mix.Tasks.Format.formatter_for_file("flow.ex", dot_formatter: @formatter_path)

    source = "step(1)\nstate(:count)\noutput(result(\"value\"))\nEnum.map(items, fun)\n"
    assert formatter.(source) == source
  end

  test "inline declarations with parentheses remain stable" do
    {formatter, _opts} =
      Mix.Tasks.Format.formatter_for_file("flow.ex", dot_formatter: @formatter_path)

    source = """
    step("one", name <- input(:name), do: {:ok, %{name: name}})
    step("two", [a <- input(:a), b <- input(:b)], do: {:ok, %{sum: a + b}})
    step("list", [a <- input(:a), b <- input(:b), c <- input(:c)], do: {:ok, %{sum: a + b + c}})
    step("empty", [], do: {:ok, %{ready: true}})

    step(
      "configured",
      value <- input(:value),
      inline: [context: ctx],
      do: {:ok, %{value: value, context: ctx}}
    )
    """

    assert formatter.(source) == source
    assert formatter.(formatter.(source)) == source
  end
end
