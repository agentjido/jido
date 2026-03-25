defmodule Jido.DocsExamplesTest do
  use ExUnit.Case, async: true

  @invalid_doctest_placeholder ~r/iex>.*\n\s*(?:\[.*\.\.\.|%[A-Za-z0-9_.]+\{.*\.\.\.\}|\{:error,\s*\.\.\.\}|\*\* \([^)]+\).*\.\.\.)/m

  test "generated agent accessor docs do not emit doctest prompts" do
    docs = function_docs(JidoTest.TestAgents.AgentWithPluginRoutes)

    for function_name <- [:plugins, :capabilities, :signal_types] do
      doc = Map.fetch!(docs, {function_name, 0})

      refute doc =~ "iex>"
      refute Regex.match?(@invalid_doctest_placeholder, doc)
    end
  end

  test "local source docs do not include placeholder outputs in iex examples" do
    offenders =
      Path.wildcard("lib/**/*.ex")
      |> Enum.filter(&File.regular?/1)
      |> Enum.flat_map(&invalid_source_docs/1)

    assert offenders == []
  end

  defp function_docs(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, docs} ->
        docs
        |> Enum.flat_map(fn
          {{:function, name, arity}, _, _, %{"en" => doc}, _} -> [{{name, arity}, doc}]
          _ -> []
        end)
        |> Map.new()

      {:error, reason} ->
        flunk("could not fetch docs for #{inspect(module)}: #{inspect(reason)}")
    end
  end

  defp invalid_source_docs(path) do
    case File.read(path) do
      {:ok, contents} ->
        if Regex.match?(@invalid_doctest_placeholder, contents), do: [path], else: []

      {:error, reason} ->
        flunk("could not read #{path}: #{inspect(reason)}")
    end
  end
end
