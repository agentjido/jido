defmodule JidoTest.System.Services.RedisClient do
  @moduledoc false

  def command(port, parts) when is_integer(port) and is_list(parts) do
    with {:ok, socket} <-
           :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false, packet: :line], 5_000) do
      try do
        :ok = :gen_tcp.send(socket, encode(parts))
        reply(socket)
      after
        :gen_tcp.close(socket)
      end
    end
  end

  defp encode(parts) do
    values = Enum.map(parts, &["$", Integer.to_string(byte_size(&1)), "\r\n", &1, "\r\n"])
    ["*", Integer.to_string(length(parts)), "\r\n", values]
  end

  defp reply(socket) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, <<"+", line::binary>>} -> {:ok, trim(line)}
      {:ok, <<"-", line::binary>>} -> {:error, trim(line)}
      {:ok, <<":", line::binary>>} -> {:ok, line |> trim() |> String.to_integer()}
      {:ok, <<"$-1\r\n">>} -> {:ok, nil}
      {:ok, <<"$", line::binary>>} -> bulk(socket, line)
      {:error, reason} -> {:error, reason}
    end
  end

  defp bulk(socket, line) do
    length = line |> trim() |> String.to_integer()
    :inet.setopts(socket, packet: :raw)

    case :gen_tcp.recv(socket, length + 2, 5_000) do
      {:ok, <<value::binary-size(^length), "\r\n">>} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  defp trim(line), do: String.trim_trailing(line, "\r\n")
end
