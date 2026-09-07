defmodule JidoTest.FactorySSE do
  @moduledoc "Local HTTP/SSE server for the real ReqLLM streaming transport."
  use GenServer

  def start_link(handler), do: GenServer.start_link(__MODULE__, handler)
  def context(server), do: GenServer.call(server, :context)

  @impl true
  def init(handler) do
    {:ok, listener} =
      :gen_tcp.listen(0, [
        :binary,
        active: false,
        packet: :http_bin,
        ip: {127, 0, 0, 1},
        reuseaddr: true
      ])

    {:ok, {_, port}} = :inet.sockname(listener)
    {:ok, task} = Task.start_link(fn -> accept(listener, handler) end)
    {:ok, %{listener: listener, port: port, task: task}}
  end

  @impl true
  def handle_call(:context, _, state) do
    context = %{
      model: "anthropic:claude-haiku-4-5",
      stream: true,
      llm_opts: [
        api_key: "fixture-key",
        base_url: "http://127.0.0.1:#{state.port}",
        max_retries: 0,
        receive_timeout: 10_000
      ]
    }

    {:reply, context, state}
  end

  @impl true
  def terminate(_, state) do
    :gen_tcp.close(state.listener)
    Process.exit(state.task, :shutdown)
    :ok
  end

  defp accept(listener, handler) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        {:ok, {:http_request, :POST, _, _}} = :gen_tcp.recv(socket, 0, 10_000)
        length = content_length(socket, 0)
        :ok = :inet.setopts(socket, packet: :raw)
        {:ok, body} = :gen_tcp.recv(socket, length, 10_000)
        handler.(socket, Jason.decode!(body))
        :gen_tcp.close(socket)
        accept(listener, handler)

      {:error, :closed} ->
        :ok
    end
  end

  defp content_length(socket, length) do
    case :gen_tcp.recv(socket, 0, 10_000) do
      {:ok, :http_eoh} ->
        length

      {:ok, {:http_header, _, name, _, value}} ->
        length =
          if String.downcase(to_string(name)) == "content-length",
            do: String.to_integer(value),
            else: length

        content_length(socket, length)
    end
  end

  def start_text(socket) do
    start_stream(socket)
    event(socket, "content_block_start", %{index: 0, content_block: %{type: "text", text: ""}})
  end

  def start_tool(socket, name) do
    start_stream(socket)

    event(socket, "content_block_start", %{
      index: 0,
      content_block: %{type: "tool_use", id: "call_stream", name: name, input: %{}}
    })
  end

  defp start_stream(socket) do
    :ok =
      :gen_tcp.send(
        socket,
        "HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\ntransfer-encoding: chunked\r\nconnection: close\r\n\r\n"
      )

    event(socket, "message_start", %{
      message: %{
        id: "msg_stream",
        type: "message",
        role: "assistant",
        model: "claude-haiku-4-5-20251001",
        content: [],
        stop_reason: nil,
        stop_sequence: nil,
        usage: %{input_tokens: 10, output_tokens: 0}
      }
    })
  end

  def text(socket, text),
    do:
      event(socket, "content_block_delta", %{index: 0, delta: %{type: "text_delta", text: text}})

  def arguments(socket, json),
    do:
      event(socket, "content_block_delta", %{
        index: 0,
        delta: %{type: "input_json_delta", partial_json: json}
      })

  def finish(socket, reason \\ "end_turn") do
    event(socket, "content_block_stop", %{index: 0})

    event(socket, "message_delta", %{
      delta: %{stop_reason: reason, stop_sequence: nil},
      usage: %{output_tokens: 10}
    })

    event(socket, "message_stop", %{})
    :gen_tcp.send(socket, "0\r\n\r\n")
  end

  def event(socket, type, data) do
    payload = "event: #{type}\ndata: #{Jason.encode!(Map.put(data, :type, type))}\n\n"
    :gen_tcp.send(socket, [Integer.to_string(byte_size(payload), 16), "\r\n", payload, "\r\n"])
  end

  def error(socket, status, message) do
    body = Jason.encode!(%{error: %{type: "authentication_error", message: message}})

    :gen_tcp.send(
      socket,
      "HTTP/1.1 #{status} Error\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
        body
    )
  end

  def disconnect(socket), do: :gen_tcp.send(socket, "0\r\n\r\n")
end
