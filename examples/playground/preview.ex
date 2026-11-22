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
      formatter:
        {:html_multi_themes,
         language: language,
         themes: [light: "github_light", dark: "github_dark"],
         default_theme: "light-dark()",
         line_numbers: line_numbers}
    )
  end

  defp link_url(url, example, catalog, mode) do
    case URI.parse(url) do
      %URI{scheme: nil, host: nil, path: path, query: nil, fragment: fragment}
      when is_binary(path) ->
        target = Path.expand(URI.decode(path), Path.join([@examples, example.chapter, example.id]))

        lesson_file =
          Enum.find_value(catalog, fn entry ->
            directory = Path.join([@examples, entry.chapter, entry.id])

            if String.starts_with?(target, directory <> "/") do
              {entry, Path.relative_to(target, directory)}
            end
          end)

        suffix = if fragment, do: "#" <> fragment, else: ""

        case lesson_file do
          {lesson, "README.md"} ->
            lesson_url(mode, lesson.id) <> suffix

          {lesson, filename} ->
            if filename in lesson.files or filename in lesson.support_files,
              do: lesson_url(mode, lesson.id, filename) <> suffix,
              else: @source <> Path.relative_to(target, @root) <> suffix

          nil ->
            if String.starts_with?(target, @root <> "/"),
              do: @source <> Path.relative_to(target, @root) <> suffix,
              else: url
        end

      _ ->
        url
    end
  end
end
