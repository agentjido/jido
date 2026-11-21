defmodule Jido.Signal.Dispatch.HttpTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Dispatch

  test "validates the small HTTP target contract" do
    assert {:ok, opts} =
             validate_opts(
               url: "https://example.com/events",
               headers: [{"authorization", "Bearer token"}]
             )

    assert opts == [
             url: "https://example.com/events",
             headers: [{"authorization", "Bearer token"}],
             timeout: 5_000
           ]
  end

  test "rejects removed HTTP client policy" do
    for option <- [
          [method: :put],
          [retry: [max_attempts: 3]],
          [ssl_options: [verify: :verify_none]]
        ] do
      assert {:error, _reason} =
               validate_opts(Keyword.merge([url: "https://example.com/events"], option))
    end
  end

  test "rejects unsafe URLs and headers" do
    for url <- [
          "https://user:pass@example.com",
          "https://example.com/a b",
          "https://example.com/events#private",
          "https://example.com:0/events",
          "https://example.com/über",
          <<"https://example.com/", 255>>,
          "https://example.com/" <> String.duplicate("a", 8_193),
          "ftp://example.com/events",
          "/relative"
        ] do
      assert {:error, _reason} = validate_opts(url: url)
    end

    for header <- [
          {"x-test\n", "value"},
          {"x-test", "bad\nvalue"},
          {"content-type", "application/json"},
          {"connection", "keep-alive"},
          {"x-test", <<"bad", 255>>},
          {"x-test", String.duplicate("a", 8_193)},
          {"ce-type", "forged.event"}
        ] do
      assert {:error, _reason} =
               validate_opts(url: "https://example.com", headers: [header])
    end

    assert {:error, _reason} =
             validate_opts(
               url: "https://example.com",
               headers: [{"authorization", "one"}, {"Authorization", "two"}]
             )

    assert {:error, _reason} =
             validate_opts(
               url: "https://example.com",
               headers: [{String.duplicate("a", 129), "value"}]
             )

    too_many_headers =
      Enum.map(1..33, fn number -> {"x-test-#{number}", Integer.to_string(number)} end)

    assert {:error, _reason} =
             validate_opts(url: "https://example.com", headers: too_many_headers)

    large_headers =
      Enum.map(1..8, fn number -> {"x-large-#{number}", String.duplicate("a", 8_000)} end)

    assert {:error, _reason} =
             validate_opts(url: "https://example.com", headers: large_headers)
  end

  test "keeps the header byte limit and duplicate-name error order" do
    headers = for number <- 1..8, do: {"x-#{number}", String.duplicate("a", 7_997)}
    assert {:ok, _opts} = validate_opts(url: "https://example.com", headers: headers)

    over_limit = List.replace_at(headers, 7, {"x-8", String.duplicate("a", 7_998)})

    assert {:error, "must contain at most 64000 bytes"} =
             Jido.Signal.Dispatch.Http.validate_headers(over_limit, [])

    assert {:error, "must not contain duplicate header names"} =
             Jido.Signal.Dispatch.Http.validate_headers(over_limit ++ [{"X-1", "duplicate"}], [])
  end

  test "normalizes serialization and transport failures" do
    assert {:error, {:serialization, _reason}} =
             Jido.Signal.Dispatch.Http.deliver(:invalid,
               url: "http://127.0.0.1/events",
               headers: [],
               timeout: 100
             )

    url = start_closing_server()
    signal = Signal.new!("http.unavailable", %{}, source: "/test")

    assert {:error, {:transport, _reason}} =
             Dispatch.dispatch(signal, {:http, url: url})
  end

  test "posts canonical structured CloudEvents JSON through OTP httpc" do
    {url, server} = start_server(204)
    signal = Signal.new!("http.sent", %{"value" => 42}, source: "/test")

    assert :ok =
             Dispatch.dispatch(
               signal,
               {:http, url: url, headers: [{"authorization", "Bearer test"}], timeout: 2_000}
             )

    assert_receive {:http_request, ^server, request}, 1_000
    {head, body} = split_request(request)

    assert head =~ "POST /events HTTP/1.1"
    assert String.downcase(head) =~ "content-type: application/cloudevents+json"
    assert String.downcase(head) =~ "authorization: bearer test"

    assert %{
             "id" => signal_id,
             "source" => "/test",
             "specversion" => "1.0",
             "type" => "http.sent",
             "data" => %{"value" => 42}
           } = Jason.decode!(body)

    assert signal_id == signal.id
  end

  test "does not follow redirects" do
    {url, server} =
      start_server(302, "", [{"location", "http://127.0.0.1:1/redirected"}])

    signal = Signal.new!("http.redirected", %{}, source: "/test")

    assert {:error, {:http_status, 302}} =
             Dispatch.dispatch(signal, {:http, url: url, timeout: 2_000})

    assert_receive {:http_request, ^server, _request}, 1_000
  end

  test "returns status without the response body" do
    {url, server} = start_server(503, "secret response body")
    signal = Signal.new!("http.failed", %{}, source: "/test")

    assert {:error, {:http_status, 503}} =
             Dispatch.dispatch(signal, {:http, url: url, timeout: 2_000})

    assert_receive {:http_request, ^server, _request}, 1_000
  end

  defp validate_opts(opts) do
    case Dispatch.validate_opts({:http, opts}) do
      {:ok, {:http, validated}} -> {:ok, validated}
      {:error, _reason} = error -> error
    end
  end

  defp start_server(status, body \\ "", headers \\ []) do
    {:ok, listener} =
      :gen_tcp.listen(0, [
        :binary,
        active: false,
        ip: {127, 0, 0, 1},
        packet: :raw,
        reuseaddr: true
      ])

    {:ok, {_address, port}} = :inet.sockname(listener)
    parent = self()

    server =
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listener)
        {:ok, request} = read_request(socket)
        send(parent, {:http_request, self(), request})
        :ok = :gen_tcp.send(socket, response(status, body, headers))
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)

      if Process.alive?(server) do
        Process.exit(server, :kill)
      end
    end)

    {"http://127.0.0.1:#{port}/events", server}
  end

  defp start_closing_server do
    {:ok, listener} =
      :gen_tcp.listen(0, [
        :binary,
        active: false,
        ip: {127, 0, 0, 1},
        packet: :raw,
        reuseaddr: true
      ])

    {:ok, {_address, port}} = :inet.sockname(listener)

    server =
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listener)
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)

      if Process.alive?(server) do
        Process.exit(server, :kill)
      end
    end)

    "http://127.0.0.1:#{port}/events"
  end

  defp read_request(socket, received \\ <<>>) do
    case complete_request(received) do
      {:ok, request} ->
        {:ok, request}

      :more ->
        case :gen_tcp.recv(socket, 0, 2_000) do
          {:ok, chunk} -> read_request(socket, received <> chunk)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp complete_request(received) do
    case :binary.match(received, "\r\n\r\n") do
      {header_end, 4} ->
        body_start = header_end + 4
        head = binary_part(received, 0, header_end)
        content_length = content_length(head)
        request_size = body_start + content_length

        if byte_size(received) >= request_size do
          {:ok, binary_part(received, 0, request_size)}
        else
          :more
        end

      :nomatch ->
        :more
    end
  end

  defp content_length(head) do
    case Regex.run(~r/(?:^|\r\n)content-length:\s*(\d+)/i, head) do
      [_header, value] -> String.to_integer(value)
      nil -> 0
    end
  end

  defp split_request(request) do
    [head, body] = :binary.split(request, "\r\n\r\n")
    {head, body}
  end

  defp response(status, body, headers) do
    reason = if status in 200..299, do: "OK", else: "Error"

    headers =
      [{"content-length", byte_size(body)}, {"connection", "close"} | headers]
      |> Enum.map_join("", fn {name, value} -> "#{name}: #{value}\r\n" end)

    "HTTP/1.1 #{status} #{reason}\r\n#{headers}\r\n#{body}"
  end
end
