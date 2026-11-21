defmodule Jido.Examples.ExplorerLive do
  use Phoenix.LiveView

  alias Phoenix.LiveView.AsyncResult

  alias Jido.AgentServer
  alias Jido.Examples.Patterns.SupportDesk
  alias Jido.Examples.{ExplorerPreview, ExplorerRuntime, ExplorerTestRunner, StartHere.HostedExpense}

  @examples Path.expand("..", __DIR__)
  @first "00_01_validated_state"
  @first_chapter "00_start_here"

  @impl true
  def mount(_params, _session, socket) do
    catalog =
      for path <- Path.wildcard(Path.join(@examples, "[0-9][0-9]_*/[0-9][0-9]_[0-9][0-9]_*/README.md")) do
        body = File.read!(path)
        [heading | lines] = String.split(body, "\n")
        directory = Path.dirname(path)

        %{
          id: Path.basename(directory),
          chapter: Path.basename(Path.dirname(directory)),
          title: String.replace(heading, ~r/^#\s+(?:\d{2}_\d{2}\s+)?/, ""),
          body: String.trim(body),
          summary:
            lines
            |> Enum.drop_while(&(String.trim(&1) == ""))
            |> Enum.take_while(&(String.trim(&1) != ""))
            |> Enum.join(" "),
          files: File.ls!(directory) |> Enum.filter(&String.ends_with?(&1, [".ex", ".exs", ".livemd"])) |> Enum.sort()
        }
      end

    {:ok,
     assign(socket,
       catalog: catalog,
       query: "",
       selected: nil,
       file: nil,
       result: nil,
       agent: nil,
       desk_agent: nil,
       desk_reply: nil,
       desk_status: :open,
       revision: 0,
       preview: nil,
       test_run: nil,
       test_lesson: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    selected = Enum.find(socket.assigns.catalog, &(&1.id == Map.get(params, "lesson", @first)))

    mode =
      if params["mode"] == "browse" or (selected && selected.chapter != @first_chapter),
        do: :browse,
        else: :learn

    file =
      with %{files: files} <- selected,
           filename when is_binary(filename) <- params["file"],
           true <- filename in files do
        filename
      else
        _ -> nil
      end

    preview =
      cond do
        file ->
          body = File.read!(Path.join([@examples, selected.chapter, selected.id, file]))
          ExplorerPreview.source(body, file)

        selected ->
          ExplorerPreview.readme(selected, socket.assigns.catalog, mode)

        true ->
          nil
      end

    {:noreply, assign(socket, selected: selected, file: file, preview: preview, mode: mode)}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, assign(socket, :query, query)}
  end

  def handle_event("chapter", %{"chapter" => chapter}, socket) do
    case Enum.find(socket.assigns.catalog, &(&1.chapter == chapter)) do
      nil -> {:noreply, socket}
      example -> {:noreply, push_patch(assign(socket, :query, ""), to: ExplorerPreview.lesson_url(:browse, example.id))}
    end
  end

  def handle_event("run_test", _params, socket) do
    case socket.assigns do
      %{test_run: %AsyncResult{loading: loading}} when loading != nil ->
        {:noreply, socket}

      %{selected: %{id: id, files: files} = lesson} ->
        if Enum.any?(files, &String.ends_with?(&1, "_test.exs")) do
          path = lesson_path(lesson)

          {:noreply,
           socket
           |> assign(test_run: AsyncResult.loading(), test_lesson: id)
           |> start_async(:lesson_test, fn -> ExplorerTestRunner.run(path) end)}
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("submit_expense", %{"amount" => amount}, socket) do
    with {cents, ""} <- Integer.parse(amount),
         {:ok, server} <- expense_server(socket.assigns.agent) do
      signal = HostedExpense.submit_signal!(%{report_id: "expense-demo", amount_cents: cents})
      outcome = AgentServer.call(server, signal)
      snapshot = AgentServer.snapshot(server)

      status =
        case outcome do
          {:ok, %AgentServer.TurnResult{status: :committed}} -> "Turn committed"
          _ -> "Turn failed. Committed state stays the same."
        end

      {:noreply,
       assign(socket,
         agent: server,
         revision: snapshot.agent_revision,
         result: %{status: status, state: snapshot.agent.state}
       )}
    else
      _ -> {:noreply, put_flash(socket, :error, "Enter a whole amount in cents and try again.")}
    end
  end

  def handle_event("desk_message", %{"message" => message, "scenario" => scenario}, socket) do
    with_desk(socket, fn socket ->
      options = if scenario == "unsafe", do: %{offline_response: "unsafe"}, else: %{}
      signal = SupportDesk.request_signal!(%{input: message, options: options})

      case AgentServer.call(socket.assigns.desk_agent, signal,
             context: %{jido_ai_inference_client: SupportDesk.ScriptedClient}
           ) do
        {:ok, %{reply: %{data: reply}}} -> assign(socket, :desk_reply, reply)
        _ -> put_flash(socket, :error, "The support request failed.")
      end
    end)
  end

  def handle_event("desk_status", %{"status" => status}, socket) when status in ["resolved", "escalated"] do
    with_desk(socket, fn socket ->
      status = String.to_existing_atom(status)
      signal = SupportDesk.update_ticket_signal!(%{ticket_status: status})

      case AgentServer.call(socket.assigns.desk_agent, signal) do
        {:ok, %{status: :committed}} -> assign(socket, :desk_status, status)
        _ -> put_flash(socket, :error, "The ticket status did not change.")
      end
    end)
  end

  defp with_desk(socket, action) do
    case ensure_desk(clear_flash(socket, :error)) do
      {:ok, socket} -> {:noreply, action.(socket)}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, "The Support Desk could not start.")}
    end
  end

  defp ensure_desk(%{assigns: %{desk_agent: server}} = socket) when is_pid(server), do: {:ok, socket}

  defp ensure_desk(socket) do
    id = "explorer-desk-#{System.unique_integer([:positive, :monotonic])}"

    with {:ok, server} <- Jido.start_agent(ExplorerRuntime, SupportDesk, id: id) do
      {:ok, assign(socket, :desk_agent, server)}
    end
  end

  @impl true
  def handle_async(:lesson_test, {:ok, {:ok, result}}, socket) do
    {:noreply, assign(socket, :test_run, AsyncResult.ok(socket.assigns.test_run, result))}
  end

  def handle_async(:lesson_test, {:ok, {:error, reason}}, socket) do
    {:noreply, assign(socket, :test_run, AsyncResult.failed(socket.assigns.test_run, reason))}
  end

  def handle_async(:lesson_test, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :test_run, AsyncResult.failed(socket.assigns.test_run, "The test runner stopped."))}
  end

  @impl true
  def terminate(_reason, socket) do
    for server <- [socket.assigns[:agent], socket.assigns[:desk_agent]], is_pid(server) do
      Jido.stop_agent(ExplorerRuntime, server)
    end

    :ok
  end

  defp expense_server(server) when is_pid(server), do: {:ok, server}

  defp expense_server(nil) do
    id = "explorer-expense-#{System.unique_integer([:positive, :monotonic])}"
    Jido.start_agent(ExplorerRuntime, HostedExpense, id: id)
  end

  defp desk_reply_label(:completed), do: "Support reply"
  defp desk_reply_label(:blocked), do: "Reply blocked"
  defp desk_reply_label(:failed), do: "Support request failed"

  defp matches?(example, query) do
    searchable = String.downcase("#{example.title} #{example.summary} #{String.replace(example.chapter, "_", " ")}")
    Enum.all?(String.split(String.downcase(query)), &String.contains?(searchable, &1))
  end

  defp lesson_path(example), do: "examples/#{example.chapter}/#{example.id}"
  defp command(example), do: "mix test.examples #{lesson_path(example)} --warnings-as-errors"

  defp chapter_title(chapter) do
    chapter
    |> String.replace(~r/^\d{2}_/, "")
    |> String.replace("_", " ")
    |> String.capitalize()
    |> String.replace("Ai", "AI")
    |> String.replace(" rag ", " RAG ")
  end

  @impl true
  def render(assigns) do
    selected = assigns.selected
    chapter = if selected, do: selected.chapter, else: @first_chapter
    learn? = assigns.mode == :learn
    learn_lesson = if chapter == @first_chapter && selected, do: selected.id, else: @first
    browse_lesson = if selected, do: selected.id, else: @first

    lessons =
      cond do
        learn? -> Enum.filter(assigns.catalog, &(&1.chapter == @first_chapter))
        String.trim(assigns.query) != "" -> Enum.filter(assigns.catalog, &matches?(&1, assigns.query))
        true -> Enum.filter(assigns.catalog, &(&1.chapter == chapter))
      end

    assigns =
      assign(assigns,
        chapter: chapter,
        chapters: assigns.catalog |> Enum.map(& &1.chapter) |> Enum.uniq(),
        lessons: lessons,
        learn?: learn?,
        learn_lesson: learn_lesson,
        browse_lesson: browse_lesson
      )

    ~H"""
    <style>
      :root { color-scheme:light; --ink:#1f2a24; --muted:#5b6660; --line:#e2ddd0; --accent:#2f6b4f; --selected:#e3ede6; --fail:#a3412e; }
      * { box-sizing:border-box; }
      body { margin:0; background:#faf8f3; color:var(--ink); font:16px/1.6 system-ui,sans-serif; }
      main { max-width:1150px; margin:auto; padding:1.5rem clamp(1rem,4vw,3rem) 3rem; }
      h1,h2,h3,p { margin-top:0; }
      h1 { margin:0; font-size:clamp(1.75rem,4vw,2.4rem); line-height:1.15; letter-spacing:-.04em; }
      h2 { font-size:1.2rem; line-height:1.25; }
      a { color:var(--accent); }
      :focus-visible { outline:2px solid var(--accent); outline-offset:2px; }
      .brand { display:inline-block; color:var(--ink); text-decoration:none; font-weight:750; margin-bottom:1.15rem; }
      .layout { display:grid; grid-template-columns:minmax(220px,260px) minmax(0,1fr); gap:1.4rem; align-items:start; }
      .panel { min-width:0; background:white; border:1px solid var(--line); border-radius:.75rem; padding:clamp(1rem,3vw,2rem); }
      .sidebar { position:sticky; top:1rem; padding:1rem; background:#f2efe6; }
      .modes { display:flex; gap:3px; padding:3px; border-radius:8px; background:var(--line); }
      .modes a { flex:1; padding:.3rem .5rem; border-radius:6px; color:var(--muted); text-align:center; text-decoration:none; font-size:.9rem; font-weight:650; }
      .modes a[aria-current=page] { color:var(--ink); background:white; box-shadow:0 1px 2px #0001; }
      .path-label { margin:1rem 0 .4rem; font-weight:650; font-size:.9rem; }
      .browse-controls { margin-top:1rem; }
      .no-results { margin:.8rem 0 0; color:var(--muted); font-size:.9rem; }
      .sidebar label { font-size:.85rem; margin-top:.8rem; }
      .sidebar label[for=query] { margin-top:0; }
      .lesson-list { list-style:none; margin:.8rem 0 0; padding:0; }
      .lesson-list a { display:block; color:var(--ink); text-decoration:none; padding:.4rem .55rem; border-radius:.35rem; }
      .lesson-list a:hover { background:white; }
      .learn-list { list-style:decimal; padding-left:1.35rem; margin-top:0; }
      .learn-list li::marker { color:var(--muted); font-size:.85rem; }
      .lesson-list a[aria-current=page] { font-weight:700; color:var(--accent); background:var(--selected); }
      label { display:block; font-weight:650; }
      input,select,textarea { width:100%; padding:.45rem .5rem; border:1px solid #879d97; border-radius:.4rem; background:white; color:inherit; font:inherit; }
      .lesson-list { max-height:24rem; overflow:auto; }
      .lesson-title { display:flex; align-items:center; justify-content:space-between; gap:.75rem 1rem; flex-wrap:wrap; }
      .lesson-title button { flex-shrink:0; }
      pre { background:#f2f4ef; padding:.8rem; border-radius:.4rem; white-space:pre-wrap; overflow-wrap:anywhere; max-width:100%; }
      button { padding:.45rem .75rem; border:0; border-radius:.4rem; background:var(--accent); color:white; font:inherit; cursor:pointer; }
      button:hover { background:#275a42; }
      button:disabled { opacity:.65; cursor:wait; }
      .demo { border:1px solid var(--line); padding:1rem; margin:1rem 0; border-radius:.6rem; }
      .demo input { max-width:14rem; margin:.3rem .3rem .3rem 0; }
      .demo textarea,.demo select { display:block; max-width:27rem; margin:.25rem 0 .65rem; }
      #desk-reply { margin-top:.8rem; }
      .desk-controls { display:flex; flex-wrap:wrap; gap:.5rem; margin-top:.8rem; }
      .preview { overflow-wrap:anywhere; }
      .preview img { max-width:100%; }
      .preview pre { overflow:auto; white-space:pre; overflow-wrap:normal; }
      .links { display:flex; gap:.25rem .85rem; flex-wrap:wrap; border-bottom:1px solid var(--line); margin:.8rem 0 1.15rem; }
      .links a { color:var(--muted); text-decoration:none; padding:.35rem 0; font-size:.9rem; }
      .links a[aria-current=page] { color:var(--accent); font-weight:700; border-bottom:2px solid var(--accent); }
      .test-result, .terminal { margin:1rem 0; }
      .test-result { border:1px solid var(--line); border-left:3px solid var(--accent); border-radius:6px; padding:.75rem; }
      .test-result[data-failed=true] { border-left-color:var(--fail); }
      .test-result p { margin:0; }
      .test-result pre { max-height:20rem; overflow:auto; margin-bottom:0; }
      .terminal summary { cursor:pointer; color:var(--muted); font-size:.9rem; }
      @media (max-width:680px) {
        .layout { grid-template-columns:minmax(0,1fr); }
        .sidebar { position:static; }
        .lesson-list { max-height:12rem; }
        .modes a { padding:.5rem; }
      }
    </style>
    <main>
      <.link patch="/" class="brand">Jido Example Explorer</.link>
      <div class="layout">
        <nav class="panel sidebar" aria-label="Example catalog">
          <div class="modes" aria-label="Explorer mode" role="group">
            <.link patch={ExplorerPreview.lesson_url(:learn, @learn_lesson)} aria-current={if @learn?, do: "page"}>
              Learn
            </.link>
            <.link patch={ExplorerPreview.lesson_url(:browse, @browse_lesson)} aria-current={if !@learn?, do: "page"}>
              Browse
            </.link>
          </div>
          <p :if={@learn?} class="path-label">Build an expense approval Agent</p>
          <div :if={!@learn?} class="browse-controls">
            <form phx-change="search">
              <label for="query">Search examples</label>
              <input id="query" name="query" type="search" value={@query} placeholder="Approval, recovery…" phx-debounce="150" />
            </form>
            <form phx-change="chapter">
              <label for="chapter">Chapter</label>
              <select id="chapter" name="chapter">
                <option :for={chapter <- @chapters} value={chapter} selected={chapter == @chapter}>
                  {chapter_title(chapter)}
                </option>
              </select>
            </form>
            <p :if={@lessons == []} class="no-results" role="status">No examples match.</p>
          </div>
          <ol :if={@learn?} class="lesson-list learn-list">
            <li :for={example <- @lessons}>
              <.link patch={ExplorerPreview.lesson_url(:learn, example.id)} aria-current={if @selected && @selected.id == example.id, do: "page"}>
                {example.title}
              </.link>
            </li>
          </ol>
          <ul :if={!@learn?} class="lesson-list">
            <li :for={example <- @lessons}>
              <.link patch={ExplorerPreview.lesson_url(:browse, example.id)} aria-current={if @selected && @selected.id == example.id, do: "page"}>
                {example.title}
              </.link>
            </li>
          </ul>
        </nav>
        <article :if={@selected} class="panel">
          <div class="lesson-title">
            <h1>{@selected.title}</h1>
            <button type="button" phx-click="run_test" disabled={@test_run && @test_run.loading != nil}>
              {if @test_run && @test_run.loading, do: "Running test…", else: "Run test"}
            </button>
          </div>
          <nav class="links" aria-label="Lesson files">
            <.link patch={ExplorerPreview.lesson_url(@mode, @selected.id)} aria-current={if !@file, do: "page"}>Lesson</.link>
            <.link :for={file <- @selected.files} patch={ExplorerPreview.lesson_url(@mode, @selected.id, file)} aria-current={if @file == file, do: "page"}>{file}</.link>
          </nav>
          <div :if={@test_lesson == @selected.id && @test_run} class="test-result"
            data-failed={to_string(@test_run.failed != nil or (@test_run.ok? && @test_run.result.status != 0))}
            aria-live="polite" id="test-result">
            <p :if={@test_run.loading}>Running the selected example.</p>
            <p :if={@test_run.failed}>{@test_run.failed}</p>
            <div :if={@test_run.ok?}>
              <strong>{if @test_run.result.status == 0, do: "Test passed", else: "Test failed (exit #{@test_run.result.status})"}</strong>
              <pre>{@test_run.result.output}</pre>
            </div>
          </div>
          <section :if={!@file && @selected.id == "00_05_hosted_agent"} class="demo">
            <h3>Try the hosted Agent</h3>
            <p>Submit 12,500 cents for automatic review, 50,000 for manual review, or zero to see a failed Turn.</p>
            <form phx-submit="submit_expense">
              <label for="amount">Amount in cents</label>
              <input id="amount" name="amount" type="number" value="12500" required />
              <button>Submit expense</button>
            </form>
            <p :if={@flash["error"]} role="alert">{@flash["error"]}</p>
            <div :if={@result} aria-live="polite" id="demo-result">
              <strong>{@result.status}</strong>
              <pre>Revision {@revision}{"\n"}{inspect(@result.state, pretty: true)}</pre>
            </div>
          </section>
          <section :if={!@file && @selected.id == "24_09_support_desk"} class="demo">
            <h2>Try the Support Desk</h2>
            <p id="desk-status">Ticket status: {String.capitalize(to_string(@desk_status))}</p>
            <form phx-submit="desk_message">
              <label for="desk-message">Customer message</label>
              <textarea id="desk-message" name="message" rows="2" maxlength="500" required>My printer is offline.</textarea>
              <label for="desk-scenario">Offline model reply</label>
              <select id="desk-scenario" name="scenario">
                <option value="tool">Troubleshoot with a tool</option>
                <option value="unsafe">Claim the ticket is resolved</option>
              </select>
              <button>Send message</button>
            </form>
            <p :if={@flash["error"]} role="alert">{@flash["error"]}</p>
            <div :if={@desk_reply} id="desk-reply" aria-live="polite">
              <strong>{desk_reply_label(@desk_reply.status)}</strong>
              <p>{if @desk_reply.status == :completed, do: @desk_reply.output, else: @desk_reply.reason}</p>
            </div>
            <div class="desk-controls">
              <button type="button" phx-click="desk_status" phx-value-status="resolved">Mark resolved</button>
              <button type="button" phx-click="desk_status" phx-value-status="escalated">Request human support</button>
            </div>
          </section>
          <div class="preview">{@preview}</div>
          <details class="terminal">
            <summary>Run from the terminal</summary>
            <pre id="test-command">{command(@selected)}</pre>
            <button id="copy-command" onclick="navigator.clipboard.writeText(document.querySelector('#test-command').textContent.trim()).then(() => this.textContent = 'Copied', () => this.textContent = 'Select the command to copy')">Copy command</button>
          </details>
        </article>
        <article :if={!@selected} class="panel">
          <h2>Example unavailable</h2>
          <.link patch="/">Open the first lesson</.link>
        </article>
      </div>
    </main>
    """
  end
end
