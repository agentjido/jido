defmodule Jido.AI.Browser.TransportTest do
  use Covenant.Case, component: "jido_ai.tools", async: true

  alias Jido.AI.Browser.Transport

  @moduletag obligation: "jido_ai.tools.I7"

  test "the pinned address receives the request with the original host" do
    {uri, server} = serve("HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\npage")
    assert {:ok, %{status: 200, body: "page"}} = get(uri, 1_000, 4)
    assert Task.await(server) =~ "host: source.invalid:"
  end

  test "a chunked body cannot exceed the byte limit" do
    {uri, server} = serve("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\npage\r\n2\r\n!!\r\n0\r\n\r\n")
    assert {:error, :response_too_large} = get(uri, 1_000, 5)
    Task.await(server)
  end

  test "a stalled response stops at the deadline" do
    {uri, server} = serve(nil)
    assert {:error, :timeout} = get(uri, 200, 5)
    assert is_binary(Task.await(server))
  end

  defp serve(response) do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(listener)

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 1_000)
        {:ok, request} = :gen_tcp.recv(socket, 0, 1_000)

        if response do
          :ok = :gen_tcp.send(socket, response)
        else
          assert {:error, :closed} = :gen_tcp.recv(socket, 0, 1_000)
        end

        :ok = :gen_tcp.close(socket)
        String.downcase(request)
      end)

    {%URI{host: "source.invalid", scheme: "http", port: port, path: "/page"}, server}
  end

  defp get(uri, timeout, limit) do
    Transport.get(uri, {127, 0, 0, 1}, [], System.monotonic_time(:millisecond) + timeout, limit)
  end
end
