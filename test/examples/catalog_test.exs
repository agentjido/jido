Code.require_file("support/catalog.exs", __DIR__)

defmodule JidoTest.Examples.CatalogTest do
  use ExUnit.Case, async: true

  @moduletag :example
  @root Path.expand("../..", __DIR__)
  @catalog Path.join(__DIR__, "catalog.yml")

  alias JidoTest.Examples.Catalog

  test "the checked-in example register is complete" do
    assert Catalog.validate(Catalog.load!(@catalog), @root) == []
  end

  test "the package compiler does not include the example source tree" do
    paths = Mix.Project.config() |> Keyword.fetch!(:elixirc_paths) |> Enum.map(&Path.expand/1)
    refute Path.expand("examples") in paths
    refute Enum.any?(paths, &String.starts_with?(&1, Path.expand("examples") <> "/"))
    refute Code.ensure_loaded?(Jido.Examples.GraphFirst.Agent)
  end

  test "a complete registered example is accepted" do
    with_fixture(fn root, catalog ->
      assert Catalog.validate(catalog, root) == []
    end)
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
      duplicate = %{entry | "source" => "examples/flow/basics/echo/second.ex"}
      File.write!(Path.join(root, duplicate["source"]), "defmodule Fixture.Second, do: nil\n")
      invalid = %{catalog | "examples" => [entry, duplicate]}
      errors = Catalog.validate(invalid, root)
      assert "duplicate example id: flow/basics/echo" in errors
      assert "duplicate example readme: examples/flow/basics/echo/README.md" in errors
      assert "duplicate example test: test/examples/flow/basics/echo_test.exs" in errors
    end)
  end

  test "unlisted source, README, test, and top-level paths are rejected" do
    with_fixture(fn root, catalog ->
      write!(root, "examples/flow/basics/orphan.ex", "defmodule Fixture.Orphan, do: nil\n")
      write!(root, "examples/flow/basics/orphan/README.md", "# Orphan\n")
      write!(root, "test/examples/flow/basics/orphan_test.exs", tagged_test())
      write!(root, "examples/unknown/example.ex", "defmodule Fixture.Unknown, do: nil\n")

      errors = Catalog.validate(catalog, root)
      assert "unlisted example source: examples/flow/basics/orphan.ex" in errors
      assert "unlisted example README: examples/flow/basics/orphan/README.md" in errors
      assert "unlisted example test: test/examples/flow/basics/orphan_test.exs" in errors
      assert "unlisted top-level example path: examples/unknown" in errors
    end)
  end

  test "paired tests must use the example tag and deferred setup loader" do
    with_fixture(fn root, catalog ->
      path = catalog["examples"] |> hd() |> Map.fetch!("test")
      File.write!(Path.join(root, path), "defmodule Fixture.BadTest, do: nil\n")
      errors = Catalog.validate(catalog, root)
      assert "paired test has no :example tag: #{path}" in errors
      assert "paired test does not use the example loader: #{path}" in errors
      assert "paired test does not load its source in setup_all: #{path}" in errors
    end)
  end

  defp with_fixture(test) do
    root = Path.join(System.tmp_dir!(), "jido-example-catalog-#{System.unique_integer([:positive])}")

    try do
      entry = %{
        "id" => "flow/basics/echo",
        "category" => "flow",
        "readme" => "examples/flow/basics/echo/README.md",
        "source" => "examples/flow/basics/echo/echo.ex",
        "test" => "test/examples/flow/basics/echo_test.exs"
      }

      write!(root, entry["readme"], "# Echo\n")
      write!(root, entry["source"], "defmodule Fixture.Echo, do: nil\n")
      write!(root, entry["test"], tagged_test())
      write!(root, "examples/README.md", "# Catalog\n")

      catalog = %{
        "version" => 1,
        "id_pattern" => "^[a-z][a-z0-9_]*(/[a-z][a-z0-9_]*)+$",
        "categories" => [
          %{
            "id" => "flow",
            "source_root" => "examples/flow",
            "test_root" => "test/examples/flow"
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

  defp tagged_test do
    """
    defmodule Fixture.EchoTest do
      use ExUnit.Case
      @moduletag :example
      setup_all do
        JidoTest.Examples.Loader.require_source!("flow/basics/echo/echo.ex")
        :ok
      end
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
