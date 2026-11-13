defmodule Jido.Persistence.Codec.Term do
  @moduledoc """
  Compact Erlang term codec for compatible application releases.

  Each value includes a small list of referenced modules. Decode loads those
  modules before safe term decoding, so static atoms from an unloaded module
  are available on another node in the same compatible release. Other atoms
  must already exist. Trusted internal execution records can request trusted
  decoding explicitly.
  """

  @behaviour Jido.Persistence.Codec

  @magic "JIDO_TERM_V1"
  @max_header_size 1_000_000
  @max_modules 10_000

  @impl true
  def id, do: "jido.term"

  @impl true
  def version, do: 1

  @impl true
  def encode(value) do
    modules = value |> modules(MapSet.new()) |> MapSet.to_list() |> Enum.sort()
    header = JSON.encode!(%{"modules" => modules})
    payload = :erlang.term_to_binary(value, [:deterministic])
    {:ok, <<@magic, byte_size(header)::unsigned-big-32, header::binary, payload::binary>>}
  rescue
    error -> {:error, {:persistence_encode_failed, __MODULE__, error}}
  end

  @impl true
  def decode(<<@magic, header_size::unsigned-big-32, rest::binary>>, opts) when is_list(opts) do
    with true <- header_size <= @max_header_size and header_size <= byte_size(rest),
         <<header::binary-size(^header_size), payload::binary>> <- rest,
         {:ok, %{"modules" => module_names} = decoded_header} <- JSON.decode(header),
         true <- map_size(decoded_header) == 1 and is_list(module_names),
         :ok <- load_modules(module_names) do
      options = if Keyword.get(opts, :trusted, false), do: [], else: [:safe]
      {:ok, :erlang.binary_to_term(payload, options)}
    else
      _ -> {:error, {:invalid_persistence_term, :envelope}}
    end
  rescue
    error -> {:error, {:persistence_decode_failed, __MODULE__, error}}
  end

  def decode(value, _opts), do: {:error, {:invalid_persistence_bytes, value}}

  defp load_modules(names) do
    if length(names) <= @max_modules and length(names) == length(Enum.uniq(names)) and
         Enum.all?(names, &is_binary/1) do
      Enum.reduce_while(names, :ok, fn name, :ok ->
        case Jido.Persistence.Codec.load_module(name) do
          {:ok, _module} -> {:cont, :ok}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    else
      {:error, {:invalid_persistence_term, :modules}}
    end
  end

  defp modules(%{__struct__: module} = value, acc) do
    value
    |> Map.from_struct()
    |> modules(add_module(acc, module))
  end

  defp modules(value, acc) when is_map(value) do
    Enum.reduce(value, acc, fn {key, item}, found ->
      found |> then(&modules(key, &1)) |> then(&modules(item, &1))
    end)
  end

  defp modules([], acc), do: acc
  defp modules([head | tail], acc), do: modules(tail, modules(head, acc))
  defp modules(value, acc) when is_tuple(value), do: value |> Tuple.to_list() |> Enum.reduce(acc, &modules/2)
  defp modules(value, acc) when is_atom(value), do: add_module(acc, value)
  defp modules(_value, acc), do: acc

  defp add_module(acc, value) do
    name = Atom.to_string(value)

    if String.starts_with?(name, "Elixir.") and Code.ensure_loaded?(value),
      do: MapSet.put(acc, name),
      else: acc
  end
end
