defmodule Jido.Examples.ExplorerPreview do
  @moduledoc false

  @examples Path.expand("..", __DIR__)
  @root Path.dirname(@examples)
  @source "https://github.com/agentjido/jido/blob/main/"

  def lesson_url(mode, lesson, file \\ nil) do
    params = [lesson: lesson]
    params = if mode == :browse, do: [{:mode, "browse"} | params], else: params
    params = if file, do: params ++ [file: file], else: params
    "/?" <> URI.encode_query(params)
  end

  def readme(example, catalog, mode) do
    options = [extension: [table: true, strikethrough: true, tasklist: true]]

    document =
      case MDEx.parse_document!(example.body, options) do
        %{nodes: [%MDEx.Heading{level: 1} | nodes]} = document -> %{document | nodes: nodes}
        document -> document
      end

    document
    |> MDEx.traverse_and_update(fn
      %MDEx.Link{} = link ->
        %{link | url: link_url(link.url, example, catalog, mode)}

      %MDEx.CodeBlock{info: info, literal: body} = block when info in ["elixir", "ex", "exs"] ->
        case highlight(body, "elixir", false) do
          {:ok, html} -> %MDEx.Raw{literal: html}
          {:error, _} -> block
        end

      node ->
        node
    end)
    |> MDEx.to_html!(syntax_highlight: false)
    |> Phoenix.HTML.raw()
  end

  def source(body, filename) do
    language = if Path.extname(filename) == ".livemd", do: "markdown", else: "elixir"

    case highlight(body, language, true) do
      {:ok, html} ->
        Phoenix.HTML.raw(html)

      {:error, _} ->
        {:safe, escaped} = Phoenix.HTML.html_escape(body)
        Phoenix.HTML.raw(["<pre><code>", escaped, "</code></pre>"])
    end
  end

  defp highlight(body, language, line_numbers) do
    Lumis.highlight(body,
      formatter: {:html_inline, [language: language, theme: "github_light", line_numbers: line_numbers]}
    )
  end

  defp link_url(url, example, catalog, mode) do
    case URI.parse(url) do
      %URI{scheme: nil, host: nil, path: path, query: nil, fragment: fragment}
      when is_binary(path) ->
        target = Path.expand(URI.decode(path), Path.join([@examples, example.chapter, example.id]))
        filename = Path.basename(target)

        lesson =
          Enum.find(catalog, fn entry ->
            Path.join([@examples, entry.chapter, entry.id]) == Path.dirname(target)
          end)

        suffix = if fragment, do: "#" <> fragment, else: ""

        cond do
          lesson && filename == "README.md" -> lesson_url(mode, lesson.id) <> suffix
          lesson && filename in lesson.files -> lesson_url(mode, lesson.id, filename) <> suffix
          String.starts_with?(target, @root <> "/") -> @source <> Path.relative_to(target, @root) <> suffix
          true -> url
        end

      _ ->
        url
    end
  end
end
