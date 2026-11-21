defmodule Jido.AI.BrowserTest do
  use Covenant.Case, component: "jido_ai.tools", async: false

  import Mimic

  alias Jido.AI.Agent.Plugin
  alias Jido.AI.Browser.{Address, Fetch, Policy, Search, Transport}

  @moduletag obligation: "jido_ai.tools.I7"
  @agent_rules [%{"host" => "hexdocs.pm", "path_prefix" => "/jido/"}]
  @host_rules [%{"host" => "hexdocs.pm", "path_prefix" => "/jido/guide/"}]
  @source "https://hexdocs.pm/jido/guide/start.html"
  @ip {93, 184, 216, 34}
  @hexdocs_page """
  <!doctype html>
  <html>
    <head><title>Jido Agent Guide</title></head>
    <body>
      <nav class="sidebar"><a href="api-reference.html">API navigation</a></nav>
      <main id="main" class="content">
        <h1>Start an Agent</h1>
        <p>Read the <a href="signals.html">Signal guide</a> for details.</p>
        <pre><code class="language-elixir">agent = MyAgent.instantiate!(id: "demo")
  MyAgent.cmd(agent, signal)</code></pre>
        <table>
          <thead><tr><th>Input</th><th>Purpose</th></tr></thead>
          <tbody><tr><td>Signal</td><td>Start a Turn</td></tr></tbody>
        </table>
        <p>EXTRA_CONTENT</p>
      </main>
    </body>
  </html>
  """

  defmodule ResearchAgent do
    use Jido.AI.Agent,
      name: "browser_research",
      description: "Find and read Jido documentation."

    ai do
      reasoning Jido.AI.Reasoning.ReAct do
        instructions "Search the Jido docs, read a result, and cite its final URL."
      end

      tools do
        browser do
          allow("hexdocs.pm", path_prefix: "/jido/")
          expose([:search, :fetch])
        end
      end
    end
  end

  setup :set_mimic_global
  setup :verify_on_exit!

  setup do
    previous = Application.fetch_env(:jido, :browser)

    Application.put_env(:jido, :browser,
      allow: @host_rules,
      search: :brave,
      brave_api_key: "test-key"
    )

    on_exit(fn ->
      case previous do
        {:ok, config} -> Application.put_env(:jido, :browser, config)
        :error -> Application.delete_env(:jido, :browser)
      end
    end)

    context = %{
      plugin_inputs: %{
        Plugin => %Jido.Plugin.Input{
          prepared: %{browser: %{"allow" => @agent_rules, "expose" => ~w(search fetch)}}
        }
      }
    }

    %{context: context}
  end

  test "URL and address policies reject ambiguous and non-public destinations" do
    assert {:ok, source} = Policy.parse(@source <> "#section")
    assert URI.to_string(source) == @source
    assert Policy.allowed?(source, @agent_rules, @host_rules)

    for url <- [
          "https://hexdocs.pm/jido/start.html",
          "https://sub.hexdocs.pm/jido/guide/start.html",
          "https://hexdocs.pm/jido/guide/../start.html",
          "https://hexdocs.pm/jido/guide/%252e%252e/start.html",
          "https://hexdocs.pm/jido/guide/..;/start.html"
        ] do
      assert {:ok, uri} = Policy.parse(url)
      refute Policy.allowed?(uri, @agent_rules, @host_rules)
    end

    for url <- [
          "file:///tmp/report",
          "https://user@hexdocs.pm/jido/guide/start.html",
          "https://hexdocs.pm:8080/jido/guide/start.html",
          "https://127.1/jido/guide/start.html",
          "http://[::1]/",
          "https://hexdocs.pm/%0aheader",
          "https://hexdocs.pm\\@example.org/"
        ] do
      assert {:error, :invalid_url} = Policy.parse(url)
    end

    for address <- [
          {127, 0, 0, 1},
          {169, 254, 169, 254},
          {10, 1, 0, 1},
          {100, 64, 0, 1},
          {0, 0, 0, 0, 0, 0xFFFF, 0x7F00, 1},
          {0xFC00, 0, 0, 0, 0, 0, 0, 1}
        ] do
      refute Address.public?(address)
    end

    assert Address.public?(@ip)
    assert Address.public?({0x2606, 0x4700, 0, 0, 0, 0, 0, 0x1111})
  end

  test "a redirect must pass policy before resolving or making another connection", %{context: context} do
    expect(Address, :resolve, fn "hexdocs.pm" -> {:ok, @ip} end)

    expect(Transport, :get, fn _uri, @ip, _headers, _deadline, _max_bytes ->
      {:ok, %{status: 302, headers: [{"location", "../private.html"}], body: ""}}
    end)

    assert {:error, :destination_blocked} = Fetch.run(%{url: @source}, context)
  end

  test "a permitted redirect resolves again and returns the final URL with bounded text", %{context: context} do
    expect(Address, :resolve, 2, fn "hexdocs.pm" -> {:ok, @ip} end)

    expect(Transport, :get, 2, fn uri, @ip, _headers, _deadline, 524_288 ->
      case uri.path do
        "/jido/guide/start.html" ->
          {:ok, %{status: 302, headers: [{"location", "next.html"}], body: ""}}

        "/jido/guide/next.html" ->
          body = "<script>discard()</script><h1>Read &amp; cite</h1>" <> String.duplicate("é", 4_000)
          {:ok, %{status: 200, headers: [{"content-type", "text/html; charset=utf-8"}], body: body}}
      end
    end)

    assert {:ok, %{url: "https://hexdocs.pm/jido/guide/next.html", text: text}} = Fetch.run(%{url: @source}, context)
    assert String.starts_with?(text, "Read & cite ")
    assert String.valid?(text)
    assert byte_size(text) == 6_000
  end

  test "a blocked resolved address stops before connection", %{context: context} do
    expect(Address, :resolve, fn "hexdocs.pm" -> {:error, :destination_blocked} end)
    reject(&Transport.get/5)
    assert {:error, :destination_blocked} = Fetch.run(%{url: @source}, context)
  end

  test "host opt-in preserves HexDocs structure as Markdown within the fetch limits", %{context: context} do
    expect(Address, :resolve, 2, fn "hexdocs.pm" -> {:ok, @ip} end)

    expect(Transport, :get, 2, fn _uri, @ip, _headers, deadline, 524_288 ->
      remaining = deadline - System.monotonic_time(:millisecond)
      assert remaining in 1..8_000

      body = String.replace(@hexdocs_page, "EXTRA_CONTENT", String.duplicate("é", 4_000))
      {:ok, %{status: 200, headers: [{"content-type", "text/html; charset=utf-8"}], body: body}}
    end)

    assert {:ok, %{url: @source, text: plain}} = Fetch.run(%{url: @source}, context)
    refute plain =~ "# Start an Agent"
    refute plain =~ "\n"

    config = Application.fetch_env!(:jido, :browser)
    Application.put_env(:jido, :browser, Keyword.put(config, :fetch_format, :markdown))

    assert {:ok, %{url: @source, text: markdown}} = Fetch.run(%{url: @source}, context)
    assert markdown =~ "# Start an Agent"
    assert markdown =~ "[Signal guide](signals.html)"
    assert markdown =~ "```"
    assert markdown =~ "demo\")\nMyAgent.cmd(agent, signal)"
    assert markdown =~ "| Signal | Start a Turn |"
    refute markdown =~ "API navigation"
    assert byte_size(markdown) in 5_999..6_000
    assert String.valid?(markdown)
  end

  test "invalid host fetch format stops before resolving the page", %{context: context} do
    config = Application.fetch_env!(:jido, :browser)
    Application.put_env(:jido, :browser, Keyword.put(config, :fetch_format, :html))

    reject(&Address.resolve/1)
    assert {:error, :invalid_fetch_format} = Fetch.run(%{url: @source}, context)
  end

  test "a search result must match both allowlists", %{context: context} do
    expect(Address, :resolve, fn "api.search.brave.com" -> {:ok, @ip} end)

    expect(Transport, :get, fn uri, @ip, headers, _deadline, _limit ->
      assert URI.decode_query(uri.query)["q"] == "Jido & Agents"
      assert {"x-subscription-token", "test-key"} in headers

      results = [
        %{url: "https://example.org/", title: "Outside"},
        %{url: "https://hexdocs.pm/jido/other.html", title: "Outside host scope"},
        %{url: "http://127.0.0.1/", title: "Local"},
        %{url: @source <> "#anchor", title: " Jido  guide ", description: "Read the guide."},
        %{url: @source, title: "Duplicate"},
        %{url: @source, title: false}
      ]

      {:ok, %{status: 200, headers: [], body: Jason.encode!(%{web: %{results: results}})}}
    end)

    assert {:ok, %{results: [%{url: @source, title: "Jido guide", snippet: "Read the guide."}]}} =
             Search.run(%{query: "Jido & Agents"}, context)
  end

  test "browser Actions require an Agent declaration and host policy", %{context: context} do
    reject(&Address.resolve/1)
    assert {:error, :browser_not_configured} = Fetch.run(%{url: @source}, %{})
    Application.delete_env(:jido, :browser)
    assert {:error, :browser_not_configured} = Fetch.run(%{url: @source}, context)
  end

  test "ReAct finds a source, reads it, and cites the final URL" do
    stub(Address, :resolve, fn _host -> {:ok, @ip} end)

    expect(Transport, :get, 2, fn
      %{host: "api.search.brave.com"}, @ip, _headers, _deadline, _limit ->
        body = Jason.encode!(%{web: %{results: [%{url: @source, title: "Jido guide"}]}})
        {:ok, %{status: 200, headers: [], body: body}}

      %{host: "hexdocs.pm", path: "/jido/guide/start.html"}, @ip, headers, _deadline, _limit ->
        refute List.keymember?(headers, "x-subscription-token", 0)
        {:ok, %{status: 200, headers: [{"content-type", "text/plain"}], body: "An Agent processes a Signal in a Turn."}}
    end)

    expect(ReqLLM, :generate_text, 3, fn model, context, opts ->
      assert Enum.map(opts[:tools], & &1.name) == ["search_web", "web_fetch"]

      case ReqLLM.Context.to_list(context) |> List.last() do
        %{role: :user} ->
          tool_call(model, context, "search_web", %{query: "Jido Agent Turn"})

        %{metadata: %{tool_output: %{"results" => [%{"url" => url}]}}} ->
          tool_call(model, context, "web_fetch", %{url: url})

        %{metadata: %{tool_output: %{"url" => url, "text" => text}}} ->
          assert url == @source
          assert text == "An Agent processes a Signal in a Turn."
          reply(model, context, :stop, ReqLLM.Context.assistant("#{text} Source: #{url}"))
      end
    end)

    assert ResearchAgent.explain().tools == [Search, Fetch]
    agent = ResearchAgent.instantiate!(id: "research")
    signal = ResearchAgent.request_signal!(%{input: "How does a Jido Agent process a Signal?"})

    assert {:ok, _next, [%Jido.Agent.Directive.Reply{signal: reply}]} = ResearchAgent.cmd(agent, signal)
    assert %{status: :completed, output: output, tool_attempts: [_, _]} = reply.data
    assert output =~ @source
  end

  defp tool_call(model, context, tool, arguments) do
    call = ReqLLM.ToolCall.new(tool, tool, Jason.encode!(arguments))
    reply(model, context, :tool_calls, ReqLLM.Context.assistant("", tool_calls: [call]))
  end

  defp reply(model, context, finish_reason, message) do
    {:ok,
     %ReqLLM.Response{
       id: "browser-response",
       model: model,
       context: context,
       finish_reason: finish_reason,
       message: message
     }}
  end
end
