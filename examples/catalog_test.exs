defmodule Jido.Examples.CatalogTest do
  use ExUnit.Case, async: true

  @moduletag :integration
  @root Path.expand("..", __DIR__)
  @catalog Path.join(__DIR__, "catalog.yml")

  alias Jido.Test.Examples.Catalog

  test "the checked-in example register is complete" do
    assert Catalog.validate(Catalog.load!(@catalog), @root) == []
  end

  test "the package compiler excludes the example source tree" do
    paths = Mix.Project.config() |> Keyword.fetch!(:elixirc_paths) |> Enum.map(&Path.expand/1)
    refute Path.expand("examples") in paths
    refute Enum.any?(paths, &String.starts_with?(&1, Path.expand("examples") <> "/"))
  end

  test "a complete registered example is accepted" do
    with_fixture(fn root, catalog ->
      assert Catalog.validate(catalog, root) == []
    end)
  end

  test "every example names its proof component" do
    catalog = Catalog.load!(@catalog)

    assert Enum.all?(catalog["examples"], &is_binary(&1["component"]))
  end

  test "a missing README, source, or paired test is rejected" do
    for {field, message} <- [
          {"readme", "missing readme"},
          {"source", "missing source"},
          {"test", "missing test"}
        ] do
      with_fixture(fn root, catalog ->
        path = catalog["examples"] |> hd() |> Map.fetch!(field)
        File.rm!(Path.join(root, path))
        assert Enum.any?(Catalog.validate(catalog, root), &String.starts_with?(&1, message))
      end)
    end
  end

  test "duplicate IDs and duplicate paired assets are rejected" do
    with_fixture(fn root, catalog ->
      [entry] = catalog["examples"]
      duplicate = %{entry | "source" => "examples/01_flow_basics/01_01_echo/second.ex"}
      File.write!(Path.join(root, duplicate["source"]), "defmodule Fixture.Second, do: nil\n")
      invalid = %{catalog | "examples" => [entry, duplicate]}
      errors = Catalog.validate(invalid, root)
      assert "duplicate example id: 01_01_echo" in errors
      assert "duplicate example readme: examples/01_flow_basics/01_01_echo/README.md" in errors
      assert "duplicate example test: examples/01_flow_basics/01_01_echo/echo_test.exs" in errors
    end)
  end

  test "unlisted source, README, test, and top-level paths are rejected" do
    with_fixture(fn root, catalog ->
      write!(root, "examples/01_flow_basics/01_02_orphan/orphan.ex", "defmodule Fixture.Orphan, do: nil\n")
      write!(root, "examples/01_flow_basics/01_02_orphan/README.md", "# Orphan\n")
      write!(root, "examples/01_flow_basics/01_02_orphan/orphan_test.exs", tagged_test("orphan.ex"))
      write!(root, "examples/unknown/example.ex", "defmodule Fixture.Unknown, do: nil\n")

      errors = Catalog.validate(catalog, root)
      assert "unlisted example source: examples/01_flow_basics/01_02_orphan/orphan.ex" in errors
      assert "unlisted example README: examples/01_flow_basics/01_02_orphan/README.md" in errors
      assert "unlisted example test: examples/01_flow_basics/01_02_orphan/orphan_test.exs" in errors
      assert "unlisted top-level example path: examples/unknown" in errors
    end)
  end

  test "chapter, lesson, mirror, and catalog order are enforced" do
    with_fixture(fn root, catalog ->
      [entry] = catalog["examples"]

      invalid_chapter = %{entry | "source" => "examples/flow_basics/01_01_echo/echo.ex"}
      errors = Catalog.validate(%{catalog | "examples" => [invalid_chapter]}, root)
      assert "source chapter must use NN_chapter: examples/flow_basics/01_01_echo/echo.ex" in errors

      wrong_prefix = %{entry | "source" => "examples/01_flow_basics/02_01_echo/echo.ex"}
      errors = Catalog.validate(%{catalog | "examples" => [wrong_prefix]}, root)

      assert "source lesson chapter prefix does not match its parent: examples/01_flow_basics/02_01_echo/echo.ex" in errors

      nested = %{entry | "source" => "examples/flow/01_flow_basics/01_01_echo/echo.ex"}
      errors = Catalog.validate(%{catalog | "examples" => [nested]}, root)
      assert "source path must use NN_chapter/NN_NN_lesson: examples/flow/01_flow_basics/01_01_echo/echo.ex" in errors

      second = %{
        "id" => "02_01_second",
        "category" => "flow",
        "component" => "jido_action.flow",
        "readme" => "examples/02_flow_more/02_01_second/README.md",
        "source" => "examples/02_flow_more/02_01_second/second.ex",
        "test" => "examples/02_flow_more/02_01_second/second_test.exs"
      }

      write!(root, second["readme"], "# Second\n")
      write!(root, second["source"], "defmodule Fixture.Second, do: nil\n")
      write!(root, second["test"], tagged_test("second.ex"))

      errors = Catalog.validate(%{catalog | "examples" => [second, entry]}, root)
      assert "example entries must be sorted by id" in errors
    end)
  end

  test "paired lessons link the test and tests load their local source" do
    with_fixture(fn root, catalog ->
      readme = catalog["examples"] |> hd() |> Map.fetch!("readme")
      path = catalog["examples"] |> hd() |> Map.fetch!("test")
      File.write!(Path.join(root, readme), "# Echo\n")
      File.write!(Path.join(root, path), "defmodule Fixture.BadTest, do: nil\n")
      errors = Catalog.validate(catalog, root)
      assert "example README does not link to its paired test: #{readme}" in errors
      assert "paired test has no :integration tag: #{path}" in errors
      assert "paired test does not load its local source: #{path}" in errors
    end)
  end

  defp with_fixture(test) do
    root = Path.join(System.tmp_dir!(), "jido-example-catalog-#{System.unique_integer([:positive])}")

    try do
      entry = %{
        "id" => "01_01_echo",
        "category" => "flow",
        "component" => "jido_action.flow",
        "readme" => "examples/01_flow_basics/01_01_echo/README.md",
        "source" => "examples/01_flow_basics/01_01_echo/echo.ex",
        "test" => "examples/01_flow_basics/01_01_echo/echo_test.exs"
      }

      write!(root, entry["readme"], "# Echo\n\nSee [the test](echo_test.exs).\n")
      write!(root, entry["source"], "defmodule Fixture.Echo, do: nil\n")
      write!(root, entry["test"], tagged_test())
      write!(root, "examples/README.md", "# Catalog\n")

      catalog = %{
        "version" => 1,
        "id_pattern" => "^[0-9]{2}_[0-9]{2}_[a-z][a-z0-9_]*$",
        "categories" => [
          %{
            "id" => "flow",
            "source_root" => "examples"
          }
        ],
        "index_readmes" => [],
        "examples" => [entry],
        "exclusions" => []
      }

      test.(root, catalog)
    after
      File.rm_rf!(root)
    end
  end

  defp tagged_test(source \\ "echo.ex") do
    """
    Code.require_file("#{source}", __DIR__)

    defmodule Fixture.EchoTest do
      use ExUnit.Case
      @moduletag :integration
      test "echo", do: assert(true)
    end
    """
  end

  defp write!(root, relative, content) do
    path = Path.join(root, relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end
end
