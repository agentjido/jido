defmodule Jido.AI.Browser do
  @moduledoc """
  Stateless search and page reading for AI Agents that declare a browser block.

  Configure the host allowlist in the `:jido, :browser` application environment.
  The Agent allowlist restricts that host policy further.
  Set `:fetch_format` to `:markdown` and install `:html2markdown` to read HTML as Markdown.
  """

  alias Jido.AI.Agent.Plugin
  alias Jido.AI.Browser.{Address, Fetch, Policy, Search, Transport}

  @compile {:no_warn_undefined, Html2Markdown}

  @timeout 8_000
  @max_body 512 * 1024
  @max_text 6_000
  @max_redirects 3
  @brave_url "https://api.search.brave.com/res/v1/web/search"

  @doc false
  def normalize(%{"allow" => rules, "expose" => expose} = config) when map_size(config) == 2 do
    with {:ok, rules} <- Policy.normalize_rules(rules),
         true <- expose in [["search"], ["fetch"], ["search", "fetch"], ["fetch", "search"]] do
      {:ok, %{"allow" => rules, "expose" => expose}}
    else
      _ -> {:error, :invalid_browser_config}
    end
  end

  def normalize(_config), do: {:error, :invalid_browser_config}

  @doc false
  def tools(nil), do: []
  def tools(%{"expose" => expose}), do: Enum.map(expose, &tool/1)

  defp tool("search"), do: Search
  defp tool("fetch"), do: Fetch

  @doc false
  def search(query, context) do
    with :ok <- validate_query(query),
         {:ok, agent_rules, host_rules, config} <- policies(context, "search"),
         {:ok, key} <- brave_key(config) do
      bounded(fn deadline ->
        url = @brave_url <> "?" <> URI.encode_query(q: query, count: 10, text_decorations: false)
        # This fixed provider endpoint has a separate trust policy. Never follow a provider redirect.
        uri = URI.parse(url)

        with {:ok, %{body: body, status: 200} = response} <-
               request(uri, [{"x-subscription-token", key}, {"accept", "application/json"}], deadline),
             :ok <- unencoded(response),
             {:ok, %{} = payload} <- Jason.decode(body) do
          {:ok, %{results: normalize_results(payload, agent_rules, host_rules)}}
        else
          _error -> {:error, :search_failed}
        end
      end)
    end
  end

  @doc false
  def fetch(url, context) do
    with {:ok, agent_rules, host_rules, config} <- policies(context, "fetch"),
         {:ok, format} <- fetch_format(config),
         {:ok, uri} <- Policy.parse(url) do
      bounded(&read_page(uri, agent_rules, host_rules, format, &1, @max_redirects))
    end
  end

  defp read_page(uri, agent_rules, host_rules, format, deadline, redirects) do
    if Policy.allowed?(uri, agent_rules, host_rules) do
      case request(uri, [{"accept", "text/html, text/plain"}], deadline) do
        {:ok, %{status: 200} = response} ->
          with :ok <- unencoded(response),
               {:ok, text} <- readable(response, format) do
            {:ok, %{url: URI.to_string(uri), text: text}}
          end

        {:ok, %{status: status, headers: headers}} when status in [301, 302, 303, 307, 308] ->
          if redirects == 0 do
            {:error, :redirect_limit}
          else
            with {:ok, destination} <- Policy.redirect(uri, header(headers, "location")) do
              read_page(destination, agent_rules, host_rules, format, deadline, redirects - 1)
            end
          end

        {:ok, _response} ->
          {:error, :unexpected_http_status}

        {:error, _reason} = error ->
          error
      end
    else
      {:error, :destination_blocked}
    end
  end

  defp request(uri, headers, deadline) do
    with {:ok, address} <- Address.resolve(uri.host) do
      Transport.get(uri, address, headers, deadline, @max_body)
    end
  end

  defp bounded(fun) do
    deadline = System.monotonic_time(:millisecond) + @timeout
    task = Task.async(fn -> fun.(deadline) end)

    case Task.yield(task, @timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end

  defp policies(context, operation) do
    config = Application.get_env(:jido, :browser, [])
    prepared = get_in(context, [:plugin_inputs, Plugin, Access.key(:prepared)])

    with %{browser: %{"allow" => agent_rules, "expose" => expose}} <- prepared,
         true <- operation in expose,
         true <- is_list(config) and Keyword.keyword?(config),
         {:ok, host_rules} <- Policy.normalize_rules(config[:allow]) do
      {:ok, agent_rules, host_rules, config}
    else
      _ -> {:error, :browser_not_configured}
    end
  end

  defp validate_query(query) when is_binary(query) and byte_size(query) in 1..512 do
    if String.valid?(query) and String.trim(query) != "", do: :ok, else: {:error, :invalid_query}
  end

  defp validate_query(_query), do: {:error, :invalid_query}

  defp brave_key(config) do
    with :brave <- config[:search],
         key when is_binary(key) and byte_size(key) > 0 <- config[:brave_api_key] do
      {:ok, key}
    else
      _ -> {:error, :search_not_configured}
    end
  end

  defp normalize_results(payload, agent_rules, host_rules) do
    case payload do
      %{"web" => %{"results" => results}} when is_list(results) ->
        results
        |> Enum.flat_map(&normalize_result(&1, agent_rules, host_rules))
        |> Enum.uniq_by(& &1.url)
        |> Enum.take(5)

      _ ->
        []
    end
  end

  defp normalize_result(%{"url" => url, "title" => title} = result, agent_rules, host_rules)
       when is_binary(title) do
    with {:ok, uri} <- Policy.parse(url),
         true <- Policy.allowed?(uri, agent_rules, host_rules) do
      [%{title: compact_text(title, 160), url: URI.to_string(uri), snippet: compact_text(result["description"], 350)}]
    else
      _ -> []
    end
  end

  defp normalize_result(_result, _agent_rules, _host_rules), do: []

  defp unencoded(%{headers: headers}) do
    if header(headers, "content-encoding") in [nil, "identity"], do: :ok, else: {:error, :unsupported_encoding}
  end

  defp fetch_format(config) do
    case Keyword.get(config, :fetch_format, :text) do
      :text ->
        {:ok, :text}

      :markdown ->
        if Code.ensure_loaded?(Html2Markdown), do: {:ok, :markdown}, else: {:error, :html2markdown_unavailable}

      _other ->
        {:error, :invalid_fetch_format}
    end
  end

  defp readable(%{headers: headers, body: body}, format) do
    type = headers |> header("content-type") |> to_string() |> String.split(";", parts: 2) |> hd() |> String.downcase()

    cond do
      not String.valid?(body) -> {:error, :unsupported_text_encoding}
      type == "text/html" and format == :markdown -> html_markdown(body)
      type == "text/html" -> {:ok, body |> html_text() |> compact_text(@max_text)}
      type == "text/plain" -> {:ok, compact_text(body, @max_text)}
      true -> {:error, :unsupported_content_type}
    end
  end

  defp html_markdown(body) do
    markdown = body |> Html2Markdown.convert() |> String.trim() |> truncate(@max_text)
    {:ok, markdown}
  rescue
    _error -> {:error, :markdown_conversion_failed}
  end

  defp html_text(body) do
    body
    |> String.replace(~r/<!--.*?(?:-->|\z)/s, " ")
    |> String.replace(~r/<(script|style|head|template)\b[^<>]*>.*?(?:<\/\1\s*>|\z)/is, " ")
    |> String.replace(~r/<[^<>]*>/s, " ")
    |> String.replace(~r/&(amp|lt|gt|quot|apos|nbsp|#39);/, fn entity ->
      Map.fetch!(
        %{
          "&amp;" => "&",
          "&lt;" => "<",
          "&gt;" => ">",
          "&quot;" => "\"",
          "&apos;" => "'",
          "&nbsp;" => " ",
          "&#39;" => "'"
        },
        entity
      )
    end)
  end

  defp compact_text(text, max_bytes) when is_binary(text) do
    text = text |> String.replace(~r/[\s\x00-\x1f\x7f]+/u, " ") |> String.trim()
    truncate(text, max_bytes)
  end

  defp compact_text(_text, _max_bytes), do: ""

  defp truncate(text, max_bytes) do
    binary_part(text, 0, min(byte_size(text), max_bytes)) |> String.replace_invalid("")
  end

  defp header(headers, name) do
    case for({^name, value} <- headers, do: value) do
      [] -> nil
      [value] -> value
      _ -> :ambiguous
    end
  end
end
