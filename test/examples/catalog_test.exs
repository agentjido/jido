defmodule JidoTest.Examples.CatalogTest do
  use ExUnit.Case, async: true
  @moduletag :example

  @package Path.expand("../..", __DIR__)
  @source Path.join(@package, "examples")

  defp groups do
    @source
    |> Path.join("[0-9][0-9]_*")
    |> Path.wildcard()
    |> Enum.filter(&(File.dir?(&1) and not String.starts_with?(Path.basename(&1), "99_")))
  end

  defp lessons(group) do
    group
    |> Path.join("[0-9][0-9]_[0-9][0-9]_*")
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
  end

  test "the catalog counts and section indexes match executable lesson folders" do
    catalog = File.read!(Path.join(@source, "README.md"))
    groups = groups()
    all = Enum.flat_map(groups, &lessons/1)

    [_, total, group_count] =
      Regex.run(~r/catalog has (\d+) executable examples in (\d+) groups/, catalog)

    assert String.to_integer(total) == length(all)
    assert String.to_integer(group_count) == length(groups)
    ids = Enum.map(all, &String.slice(Path.basename(&1), 0, 5))
    assert ids == Enum.uniq(ids)

    for group <- groups do
      name = Path.basename(group)
      assert [_, count] = Regex.run(~r/\| #{name} \| (\d+) \|/, catalog)
      assert String.to_integer(count) == length(lessons(group)), name
      index = File.read!(Path.join(group, "README.md"))

      for lesson <- lessons(group) do
        assert String.starts_with?(Path.basename(lesson), String.slice(name, 0, 2))
        assert index =~ "#{Path.basename(lesson)}/README.md", lesson
        assert File.regular?(Path.join(lesson, "README.md")), lesson
        assert Path.wildcard(Path.join(lesson, "**/*.ex")) != [], lesson
        tests = Path.join(__DIR__, Path.relative_to(lesson, @source))
        assert Path.wildcard(Path.join(tests, "**/*_test.exs")) != [], tests
      end
    end
  end

  test "stable test folders have a lesson and contain no skipped tests" do
    for group <- groups(), tests <- lessons(Path.join(__DIR__, Path.basename(group))) do
      source = Path.join(group, Path.basename(tests))
      assert File.dir?(source), tests

      for file <- Path.wildcard(Path.join(tests, "**/*_test.exs")) do
        refute File.read!(file) =~ ~r/@(?:module)?tag\s+(?::skip\b|skip:\s*true)/, file
      end
    end
  end

  test "repository documentation links resolve to files or folders" do
    documents =
      Path.wildcard(Path.join(@source, "**/*.md")) ++
        Path.wildcard(Path.join(__DIR__, "**/*.md"))

    broken =
      for file <- documents,
          Path.basename(file) != "AGENTS.md",
          [_, href] <- Regex.scan(~r/\]\(([^)\s]+)\)/, File.read!(file)),
          not String.starts_with?(href, "#"),
          not Regex.match?(~r/^[a-zA-Z][a-zA-Z0-9+.-]*:/, href),
          target = href |> String.split("#", parts: 2) |> hd() |> URI.decode(),
          expanded = Path.expand(target, Path.dirname(file)),
          # Sibling repositories and private demos are optional workspace content.
          String.starts_with?(expanded, @package <> "/"),
          not File.exists?(expanded),
          do: "#{Path.relative_to(file, @source)}: #{href}"

    assert broken == [], Enum.join(broken, "\n")
  end

  test "durable proposals stay outside the executable test tree" do
    proposals = Path.wildcard(Path.join(@source, "11_durable/proposals/11_*"))
    assert proposals != []

    for proposal <- proposals do
      assert File.regular?(Path.join(proposal, "README.md"))
      assert File.regular?(Path.join(proposal, "test-plan.md"))
      assert Path.wildcard(Path.join(proposal, "**/*.ex")) == []
      refute File.exists?(Path.join(__DIR__, "11_durable/#{Path.basename(proposal)}"))
    end
  end
end
