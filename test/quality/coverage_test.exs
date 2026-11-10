Code.require_file("support/contract.exs", __DIR__)
Code.require_file("support/component_proof.exs", __DIR__)
Code.require_file("support/coverage.exs", __DIR__)

defmodule Jido.Quality.CoverageTest do
  use ExUnit.Case, async: true

  alias Jido.Quality.Coverage

  @thresholds %{
    "package_minimum_percent" => 90,
    "component_minimum_percent" => 80,
    "maximum_component_regression_points" => 0.5
  }

  test "suite union counts an overlapping line once" do
    suites = [suite("unit", %{"lib/a.ex:1" => line("a", true)}), suite("property", %{"lib/a.ex:1" => line("a", true)})]
    report = Coverage.aggregate(suites, baseline(%{"a" => 100.0}), @thresholds)

    assert report["package"]["relevant_lines"] == 1
    assert report["package"]["covered_lines"] == 1
  end

  test "a line covered by one suite is its unique contribution" do
    suites = [
      suite("unit", %{"lib/a.ex:1" => line("a", true), "lib/a.ex:2" => line("a", true)}),
      suite("property", %{"lib/a.ex:1" => line("a", true)})
    ]

    report = Coverage.aggregate(suites, baseline(%{"a" => 100.0}), @thresholds)
    assert report["suites"]["unit"]["covered_lines"] == 2
    assert report["suites"]["unit"]["unique_covered_lines"] == 1
    assert report["suites"]["property"]["unique_covered_lines"] == 0
  end

  test "owned lines contribute to their component" do
    suites = [suite("unit", %{"lib/a.ex:1" => line("a", true), "lib/b.ex:1" => line("b", false)})]
    report = Coverage.aggregate(suites, baseline(%{"a" => 100.0, "b" => 0.0}), @thresholds)

    assert report["components"]["a"]["percent"] == 100.0
    assert report["components"]["b"]["percent"] == 0.0
  end

  test "a shared Covenant module contributes to each declared component" do
    shared = %{
      "component" => "primary",
      "components" => ["primary", "durable"],
      "covered" => true
    }

    suites = [suite("unit", %{"lib/a.ex:1" => shared})]
    report = Coverage.aggregate(suites, baseline(%{"primary" => 100.0, "durable" => 100.0}), @thresholds)

    assert report["components"]["primary"]["percent"] == 100.0
    assert report["components"]["durable"]["percent"] == 100.0
    assert report["package"]["relevant_lines"] == 1
  end

  test "an unmapped line fails aggregation" do
    suites = [suite("unit", %{"lib/a.ex:1" => %{"component" => nil, "covered" => true}})]
    report = Coverage.aggregate(suites, baseline(%{}), @thresholds, components: [])

    assert report["status"] == "fail"
    assert "line lib/a.ex:1 has no component owner" in report["errors"]
  end

  test "different owners for the same line fail aggregation" do
    suites = [suite("unit", %{"lib/a.ex:1" => line("a", true)}), suite("property", %{"lib/a.ex:1" => line("b", true)})]
    report = Coverage.aggregate(suites, baseline(%{"a" => 100.0, "b" => 100.0}), @thresholds)

    assert "line lib/a.ex:1 maps to both a and b" in report["errors"]
  end

  test "package coverage below 90 percent fails" do
    lines = for index <- 1..10, into: %{}, do: {"lib/a.ex:#{index}", line("a", index < 10)}
    report = Coverage.aggregate([suite("unit", lines)], baseline(%{"a" => 90.0}), @thresholds)

    refute Enum.any?(report["errors"], &String.contains?(&1, "package coverage"))

    lines = Map.put(lines, "lib/a.ex:9", line("a", false))
    report = Coverage.aggregate([suite("unit", lines)], baseline(%{"a" => 80.0}), @thresholds)
    assert Enum.any?(report["errors"], &String.contains?(&1, "package coverage 80.0%"))
  end

  test "component coverage below the fixed minimum fails" do
    lines = for index <- 1..10, into: %{}, do: {"lib/a.ex:#{index}", line("a", index < 8)}
    report = Coverage.aggregate([suite("unit", lines)], baseline(%{"a" => 70.0}), @thresholds)

    assert Enum.any?(report["errors"], &String.contains?(&1, "below 80.0%"))
  end

  test "component coverage below its recorded floor fails" do
    lines = for index <- 1..10, into: %{}, do: {"lib/a.ex:#{index}", line("a", index < 10)}
    custom = %{"components" => %{"a" => %{"baseline_percent" => 90.0, "floor_percent" => 95.0}}}
    report = Coverage.aggregate([suite("unit", lines)], custom, @thresholds)

    assert Enum.any?(report["errors"], &String.contains?(&1, "95.0% floor"))
  end

  test "component regression greater than half a point fails" do
    lines = for index <- 1..100, into: %{}, do: {"lib/a.ex:#{index}", line("a", index <= 99)}
    report = Coverage.aggregate([suite("unit", lines)], baseline(%{"a" => 100.0}), @thresholds)

    assert Enum.any?(report["errors"], &String.contains?(&1, "regressed 1.0 points"))
  end

  test "an ignored generated module does not enter the denominator" do
    report =
      Coverage.aggregate([suite("unit", %{"lib/a.ex:1" => line("a", true)})], baseline(%{"a" => 100.0}), @thresholds)

    assert report["package"]["relevant_lines"] == 1
    refute Map.has_key?(report["components"], "generated")
  end

  test "a component with no executable lines fails closed" do
    report = Coverage.aggregate([suite("unit", %{})], baseline(%{"a" => 0.0}), @thresholds)

    assert "component a has no line coverage evidence" in report["errors"]
  end

  test "the committed baseline must match the component inventory and thresholds" do
    source = baseline(%{"a" => 90.0})

    source =
      source
      |> Map.put("version", 1)
      |> Map.put("revision", String.duplicate("a", 40))
      |> Map.put("thresholds", %{
        "package_minimum_percent" => 90.0,
        "component_minimum_percent" => 80.0,
        "maximum_component_regression_points" => 0.5
      })

    assert Coverage.validate_baseline(source, ["a"], @thresholds) == []

    invalid = put_in(source, ["components", "a", "floor_percent"], 79.9)
    assert "component a has an invalid coverage floor" in Coverage.validate_baseline(invalid, ["a"], @thresholds)

    assert "coverage baseline component inventory does not match component proof" in Coverage.validate_baseline(
             source,
             ["a", "b"],
             @thresholds
           )
  end

  defp suite(id, lines), do: %{"suite" => id, "lines" => lines}
  defp line(component, covered), do: %{"component" => component, "covered" => covered}

  defp baseline(components) do
    %{
      "components" =>
        Map.new(components, fn {id, percent} ->
          {id, %{"baseline_percent" => percent, "floor_percent" => 80.0}}
        end)
    }
  end
end
