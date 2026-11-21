defmodule Jido.Examples.Patterns.LiveChat.Live do
  @moduledoc "A transient Phoenix LiveView client for one durable chat Agent."

  use Phoenix.LiveView

  alias Jido.AgentServer.Status
  alias Jido.Examples.Patterns.LiveChat

  @instance __MODULE__.Jido
  @pubsub __MODULE__.PubSub
  @task_supervisor __MODULE__.TaskSupervisor
  @operation_states [:waiting, :failed, :cancelled, :timed_out, :uncertain, :committed]

  @doc "Returns the application children used by the Playground and its tests."
  def child_specs do
    [
      {Jido,
       name: @instance,
       namespace: "examples/live-chat/playground",
       persistence: {Jido.Persistence.ETS, table: __MODULE__.Store}},
      {Phoenix.PubSub, name: @pubsub},
      {Task.Supervisor, name: @task_supervisor}
    ]
  end

  @impl true
  def mount(params, _session, socket) do
    conversation_id = Map.get(params, "conversation_id", "demo-conversation")
    {:ok, address} = LiveChat.ensure_conversation(@instance, conversation_id)
    {:ok, history} = LiveChat.history(@instance, address)
    topic = "examples:live-chat:#{conversation_id}"

    if connected?(socket), do: Phoenix.PubSub.subscribe(@pubsub, topic)

    socket =
      socket
      |> assign(
        page_title: "Offline Jido Chat",
        conversation_id: conversation_id,
        agent_address: address,
        topic: topic,
        history: history,
        operation: :committed,
        stream_text: "",
        stream_events: [],
        error: nil,
        operation_states: @operation_states
      )
      |> allow_upload(:attachment,
        accept: ~w(.jpg .jpeg .png),
        max_entries: 1,
        max_file_size: 1_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("send", %{"message" => params}, socket) do
    text = String.trim(Map.get(params, "text", ""))
    attachment = consume_attachment(socket)
    live_view = self()

    options = [
      attachment: attachment,
      fail: Map.get(params, "fail") == "true",
      response: "Offline reply: #{text}",
      stream_dispatch: {:pubsub, target: @pubsub, topic: socket.assigns.topic}
    ]

    case Task.Supervisor.start_child(@task_supervisor, fn ->
           result = LiveChat.ask(@instance, socket.assigns.agent_address, text, options)
           send(live_view, {:chat_turn_result, result})
         end) do
      {:ok, _task} ->
        {:noreply,
         assign(socket,
           operation: :waiting,
           stream_text: "",
           stream_events: [],
           error: nil
         )}

      {:error, reason} ->
        {:noreply, assign(socket, operation: :failed, error: inspect(reason))}
    end
  end

  def handle_event("cancel", _params, socket) do
    case Jido.status(@instance, socket.assigns.agent_address) do
      %Status{active_turn_id: turn_id} when is_binary(turn_id) ->
        result = Jido.cancel_turn(@instance, socket.assigns.agent_address, turn_id)

        operation =
          case result do
            :ok -> :cancelled
            {:error, _reason} -> :failed
          end

        {:noreply, assign(socket, operation: operation)}

      _status ->
        {:noreply, assign(socket, operation: :failed, error: "No active Turn to cancel")}
    end
  end

  @impl true
  def handle_info(%Jido.Signal{type: "jido.ai.model.stream.started"} = signal, socket) do
    {:noreply, record_stream_event(socket, signal)}
  end

  def handle_info(%Jido.Signal{type: "jido.ai.model.stream.chunk"} = signal, socket) do
    text = get_in(signal.data, [:chunk, :text]) || ""

    {:noreply,
     socket
     |> update(:stream_text, &(&1 <> text))
     |> record_stream_event(signal)}
  end

  def handle_info(%Jido.Signal{type: "jido.ai.model.stream.completed"} = signal, socket) do
    {:noreply, record_stream_event(socket, signal)}
  end

  def handle_info(%Jido.Signal{type: "jido.ai.model.stream.failed"} = signal, socket) do
    {:noreply,
     socket
     |> assign(operation: :failed, error: Map.get(signal.data, :reason))
     |> record_stream_event(signal)}
  end

  def handle_info({:chat_turn_result, result}, socket) do
    operation = LiveChat.operation_state(result)

    history =
      case LiveChat.history(@instance, socket.assigns.agent_address) do
        {:ok, messages} -> messages
        {:error, _reason} -> socket.assigns.history
      end

    {:noreply, assign(socket, operation: operation, history: history)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="chat-shell">
      <header>
        <p class="eyebrow">Phoenix Playground · deterministic offline model</p>
        <h1>Jido LiveView chat</h1>
        <p>
          Conversation <code>{@conversation_id}</code> uses stable Agent Address
          <code>{@agent_address.id}</code>.
        </p>
      </header>

      <section id="operation-state" class={"state state-#{@operation}"}>
        Current Turn: <strong>{@operation}</strong>
      </section>

      <ol id="history" class="history">
        <li :for={message <- @history} class={"message message-#{message.role}"}>
          <strong>{message.role}</strong>
          <p>{message.text}</p>
          <span :for={attachment <- message.attachments} class="attachment">
            attachment: {attachment.type}
          </span>
        </li>
      </ol>

      <section :if={@operation == :waiting} id="stream" class="message message-assistant">
        <strong>assistant · streaming</strong>
        <p>{@stream_text}</p>
      </section>

      <p :if={@error} id="chat-error" class="error">{@error}</p>

      <form id="chat-form" phx-submit="send">
        <label>
          Message
          <input name="message[text]" required maxlength="2000" autocomplete="off" />
        </label>

        <label>
          Optional image
          <.live_file_input upload={@uploads.attachment} />
        </label>

        <label class="failure-toggle">
          <input type="checkbox" name="message[fail]" value="true" />
          Inject model failure
        </label>

        <div class="actions">
          <button type="submit" disabled={@operation == :waiting}>Send</button>
          <button type="button" phx-click="cancel" disabled={@operation != :waiting}>Cancel Turn</button>
        </div>
      </form>

      <details>
        <summary>Ordered stream Signals</summary>
        <ol id="stream-events">
          <li
            :for={event <- @stream_events}
            data-sequence={event.sequence}
            data-signal-type={event.type}
          >
            {event.sequence}: {event.type}
          </li>
        </ol>
      </details>

      <footer>
        <span :for={state <- @operation_states} class="state-key">{state}</span>
      </footer>
    </main>

    <style>
      :root { color-scheme: light dark; font-family: ui-sans-serif, system-ui, sans-serif; }
      body { margin: 0; background: #0b1020; color: #e8ecf5; }
      .chat-shell { width: min(760px, calc(100% - 2rem)); margin: 2rem auto; }
      .eyebrow { color: #8fa3d8; text-transform: uppercase; letter-spacing: .08em; font-size: .75rem; }
      code { color: #b8c8ff; }
      .state { padding: .8rem 1rem; border: 1px solid #344366; border-radius: .6rem; margin: 1rem 0; }
      .state-committed { border-color: #4ca477; }
      .state-failed, .error { color: #ff9f9f; border-color: #d45f5f; }
      .history { display: grid; gap: .75rem; padding: 0; list-style: none; }
      .message { padding: 1rem; border-radius: .8rem; background: #17213b; }
      .message-user { margin-left: 12%; background: #25345c; }
      .message p { margin-bottom: 0; white-space: pre-wrap; }
      .attachment, .state-key { display: inline-block; margin: .3rem .3rem 0 0; padding: .2rem .45rem; border-radius: 999px; background: #33446f; font-size: .75rem; }
      form { display: grid; gap: .8rem; margin-top: 1rem; padding: 1rem; border: 1px solid #344366; border-radius: .8rem; }
      label { display: grid; gap: .35rem; }
      .failure-toggle { display: flex; align-items: center; }
      input, button { font: inherit; padding: .65rem; border-radius: .45rem; border: 1px solid #586b99; }
      .actions { display: flex; gap: .6rem; }
      button { cursor: pointer; }
      button:disabled { cursor: not-allowed; opacity: .5; }
      details, footer { margin-top: 1rem; }
    </style>
    """
  end

  defp consume_attachment(socket) do
    socket
    |> consume_uploaded_entries(:attachment, fn %{path: path}, entry ->
      data_url = "data:#{entry.client_type};base64,#{path |> File.read!() |> Base.encode64()}"
      {:ok, %{media_type: entry.client_type, data_url: data_url}}
    end)
    |> List.first()
  end

  defp record_stream_event(socket, signal) do
    event = %{sequence: signal.data.sequence, type: signal.type}
    update(socket, :stream_events, &(&1 ++ [event]))
  end
end
