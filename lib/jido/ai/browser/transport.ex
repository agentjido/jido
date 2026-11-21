defmodule Jido.AI.Browser.Transport do
  @moduledoc false

  alias Mint.HTTP

  def get(uri, address, headers, deadline, max_bytes) do
    with {:ok, timeout} <- remaining(deadline),
         {:ok, conn} <-
           HTTP.connect(scheme(uri), address, uri.port,
             hostname: uri.host,
             mode: :passive,
             protocols: [:http1],
             max_header_list_size: 16_384,
             transport_opts: transport_options(address, timeout)
           ) do
      try do
        case HTTP.request(conn, "GET", target(uri), [{"accept-encoding", "identity"} | headers], nil) do
          {:ok, conn, ref} ->
            receive_response(conn, ref, deadline, max_bytes, %{status: nil, headers: [], chunks: [], bytes: 0})

          {:error, _conn, _reason} ->
            {:error, :http_request_failed}
        end
      after
        HTTP.close(conn)
      end
    else
      {:error, :timeout} -> {:error, :timeout}
      {:error, _reason} -> {:error, :connection_failed}
    end
  end

  defp receive_response(conn, ref, deadline, max_bytes, response) do
    with {:ok, timeout} <- remaining(deadline),
         {:ok, conn, events} <- HTTP.recv(conn, 0, timeout) do
      case Enum.reduce_while(events, response, &accumulate(&1, &2, ref, max_bytes)) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
        response -> receive_response(conn, ref, deadline, max_bytes, response)
      end
    else
      {:error, :timeout} -> {:error, :timeout}
      {:error, _conn, %Mint.TransportError{reason: :timeout}, _events} -> {:error, :timeout}
      {:error, _conn, _reason, _events} -> {:error, :http_receive_failed}
    end
  end

  defp accumulate({:status, ref, status}, response, ref, _limit), do: {:cont, %{response | status: status}}

  defp accumulate({:headers, ref, _headers}, %{status: status} = response, ref, _limit)
       when status < 200 do
    {:cont, response}
  end

  defp accumulate({:headers, ref, headers}, response, ref, _limit) do
    response = %{response | headers: response.headers ++ headers}

    if response.status >= 200 and response.status != 200 do
      {:halt, {:ok, finish(response)}}
    else
      {:cont, response}
    end
  end

  defp accumulate({:data, ref, bytes}, response, ref, limit) do
    total = response.bytes + byte_size(bytes)

    if total > limit do
      {:halt, {:error, :response_too_large}}
    else
      {:cont, %{response | chunks: [bytes | response.chunks], bytes: total}}
    end
  end

  defp accumulate({:done, ref}, response, ref, _limit), do: {:halt, {:ok, finish(response)}}
  defp accumulate({:error, ref, _reason}, _response, ref, _limit), do: {:halt, {:error, :http_receive_failed}}
  defp accumulate(_event, response, _ref, _limit), do: {:cont, response}

  defp finish(response) do
    %{
      status: response.status,
      headers: response.headers,
      body: response.chunks |> Enum.reverse() |> IO.iodata_to_binary()
    }
  end

  defp remaining(deadline) do
    case deadline - System.monotonic_time(:millisecond) do
      timeout when timeout > 0 -> {:ok, timeout}
      _ -> {:error, :timeout}
    end
  end

  defp scheme(%URI{scheme: "https"}), do: :https
  defp scheme(%URI{scheme: "http"}), do: :http

  defp transport_options(address, timeout) do
    ipv6? = tuple_size(address) == 8
    [inet6: ipv6?, inet4: not ipv6?, timeout: timeout, send_timeout: timeout]
  end

  defp target(%URI{path: path, query: nil}), do: path
  defp target(%URI{path: path, query: query}), do: path <> "?" <> query
end
