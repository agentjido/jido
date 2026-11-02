defmodule Jido.Flow.SourceMapTest do
  use ExUnit.Case, async: true

  alias Jido.Flow.DSL.{Output, SourceMap, Step}
  alias Jido.Flow.Error

  test "uses the nearest parent location for a nested form error" do
    source_map = %{
      [:forms, "work"] => %{file: "flow.ex", line: 12, column: 5},
      [:output] => %{file: "flow.ex", line: 20, column: 3}
    }

    details = %{path: [:forms, "work", :params, :name]}
    assert SourceMap.lookup(source_map, details) == %{file: "flow.ex", line: 12, column: 5}

    error = Error.validation_error("invalid nested value", details)
    attached = SourceMap.attach_error(error, source_map)

    assert attached.details.file == "flow.ex"
    assert attached.details.line == 12
    assert attached.details.column == 5
    assert attached.details.path == details.path
  end

  test "records explicit entity source data for forms and output" do
    step = %Step{name: "work", __source__: %{line: 7, column: 4}}
    output = %Output{__source__: %{line: 11}}

    source_map =
      %{}
      |> SourceMap.put_entity(step, 0, "flow.ex")
      |> SourceMap.put_entity(output, :output, "flow.ex")

    assert source_map[[:forms, "work"]] == %{file: "flow.ex", line: 7, column: 4}
    assert source_map[[:output]] == %{file: "flow.ex", line: 11}

    assert SourceMap.lookup(source_map, %{step: "work"}) == source_map[[:forms, "work"]]
  end

  test "does not change an error without structured details" do
    assert SourceMap.attach_error(:invalid, %{}, [:forms, "work"]) == :invalid
  end
end
