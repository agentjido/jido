defmodule Jido.Persistence.Codec.JSON do
  @moduledoc """
  Inspectable tagged JSON codec for compatible application releases.

  The codec preserves supported Elixir terms without making Store adapters
  aware of Jido record shapes. Atoms must already exist in the running release.
  """

  @behaviour Jido.Persistence.Codec

  @tag "$jido"
  @max_depth 100
  @max_collection_size 100_000

  @impl true
  def id, do: "jido.json"

  @impl true
  def version, do: 1

  @impl true
  def encode(value) do
    with {:ok, tagged} <- tag(value, 0) do
      {:ok, JSON.encode!(%{"codec" => id(), "codec_version" => version(), "value" => tagged})}
    end
  rescue
    error -> {:error, {:persistence_encode_failed, __MODULE__, error}}
  end

  @impl true
  def decode(bytes, _opts) when is_binary(bytes) do
    with {:ok, %{"codec" => "jido.json", "codec_version" => 1, "value" => value}} <- JSON.decode(bytes),
         :ok <- preload_modules(value, 0),
         {:ok, decoded} <- untag(value, 0) do
      {:ok, decoded}
    else
      {:ok, _other} -> {:error, {:invalid_persistence_json, :envelope}}
      {:error, _reason} = error -> error
    end
  rescue
    error -> {:error, {:persistence_decode_failed, __MODULE__, error}}
  end

  def decode(value, _opts), do: {:error, {:invalid_persistence_bytes, value}}

  defp tag(_value, depth) when depth > @max_depth, do: {:error, {:persistence_json_limit, :depth}}
  defp tag(value, _depth) when is_nil(value) or is_boolean(value) or is_integer(value), do: {:ok, value}

  defp tag(value, _depth) when is_float(value), do: {:ok, value}

  defp tag(value, _depth) when is_binary(value) do
    if String.valid?(value) do
      {:ok, value}
    else
      {:ok, %{@tag => "binary", "base64" => Base.encode64(value)}}
    end
  end

  defp tag(value, _depth) when is_atom(value) do
    if Code.ensure_loaded?(value) do
      {:ok, %{@tag => "module", "name" => Atom.to_string(value)}}
    else
      {:ok, %{@tag => "atom", "name" => Atom.to_string(value)}}
    end
  end

  defp tag(value, depth) when is_tuple(value) do
    with :ok <- collection_size(tuple_size(value)),
         {:ok, items} <- map_values(Tuple.to_list(value), depth + 1, &tag/2) do
      {:ok, %{@tag => "tuple", "items" => items}}
    end
  end

  defp tag(value, depth) when is_list(value) do
    cond do
      List.improper?(value) -> {:error, {:unsupported_persistence_value, :improper_list}}
      true -> with :ok <- collection_size(length(value)), do: map_values(value, depth + 1, &tag/2)
    end
  end

  defp tag(%{__struct__: module} = value, depth) when is_atom(module) do
    with {:ok, fields} <- tag_map(Map.from_struct(value), depth + 1) do
      {:ok, %{@tag => "struct", "module" => Atom.to_string(module), "fields" => fields}}
    end
  end

  defp tag(value, depth) when is_map(value) do
    with {:ok, entries} <- tag_map(value, depth + 1), do: {:ok, %{@tag => "map", "entries" => entries}}
  end

  defp tag(value, _depth) when is_bitstring(value), do: {:error, {:unsupported_persistence_value, :bitstring}}
  defp tag(value, _depth) when is_pid(value), do: {:error, {:unsupported_persistence_value, :pid}}
  defp tag(value, _depth) when is_port(value), do: {:error, {:unsupported_persistence_value, :port}}
  defp tag(value, _depth) when is_reference(value), do: {:error, {:unsupported_persistence_value, :reference}}
  defp tag(value, _depth) when is_function(value), do: {:error, {:unsupported_persistence_value, :function}}

  defp tag_map(value, depth) do
    with :ok <- collection_size(map_size(value)) do
      value
      |> Map.to_list()
      |> Enum.reduce_while({:ok, []}, fn {key, item}, {:ok, entries} ->
        with {:ok, tagged_key} <- tag(key, depth),
             {:ok, tagged_value} <- tag(item, depth) do
          entry = %{"key" => tagged_key, "value" => tagged_value}
          {:cont, {:ok, [entry | entries]}}
        else
          {:error, _reason} = error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, entries} -> {:ok, Enum.sort_by(entries, &JSON.encode!/1)}
        error -> error
      end
    end
  end

  defp untag(_value, depth) when depth > @max_depth, do: {:error, {:persistence_json_limit, :depth}}

  defp untag(value, _depth) when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value),
    do: {:ok, value}

  defp untag(%{@tag => "binary", "base64" => encoded} = value, _depth) when map_size(value) == 2 do
    case Base.decode64(encoded) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, {:invalid_persistence_json, :binary}}
    end
  end

  defp untag(%{@tag => "atom", "name" => name} = value, _depth) when map_size(value) == 2,
    do: existing_atom(name)

  defp untag(%{@tag => "module", "name" => name} = value, _depth) when map_size(value) == 2 do
    Jido.Persistence.Codec.load_module(name)
  end

  defp untag(%{@tag => "tuple", "items" => items} = value, depth)
       when map_size(value) == 2 and is_list(items) do
    with :ok <- collection_size(length(items)),
         {:ok, decoded} <- map_values(items, depth + 1, &untag/2) do
      {:ok, List.to_tuple(decoded)}
    end
  end

  defp untag(%{@tag => "map", "entries" => entries} = value, depth)
       when map_size(value) == 2 and is_list(entries),
       do: untag_map(entries, depth + 1)

  defp untag(%{@tag => "struct", "module" => name, "fields" => entries} = value, depth)
       when map_size(value) == 3 and is_list(entries) do
    with {:ok, module} <- existing_atom(name),
         {:module, ^module} <- Code.ensure_loaded(module),
         {:ok, fields} <- untag_map(entries, depth + 1),
         :ok <- exact_struct_fields(module, fields) do
      {:ok, struct!(module, fields)}
    else
      {:error, _reason} = error -> error
      _ -> {:error, {:unavailable_persistence_module, name}}
    end
  rescue
    error -> {:error, {:invalid_persistence_struct, name, error}}
  end

  defp untag(value, depth) when is_list(value) do
    with :ok <- collection_size(length(value)), do: map_values(value, depth + 1, &untag/2)
  end

  defp untag(_value, _depth), do: {:error, {:invalid_persistence_json, :value}}

  defp untag_map(entries, depth) do
    with :ok <- collection_size(length(entries)) do
      entries
      |> Enum.reduce_while({:ok, []}, fn
        %{"key" => key, "value" => value} = entry, {:ok, pairs} when map_size(entry) == 2 ->
          with {:ok, decoded_key} <- untag(key, depth),
               {:ok, decoded_value} <- untag(value, depth) do
            {:cont, {:ok, [{decoded_key, decoded_value} | pairs]}}
          else
            {:error, _reason} = error -> {:halt, error}
          end

        _entry, _acc ->
          {:halt, {:error, {:invalid_persistence_json, :map_entry}}}
      end)
      |> case do
        {:ok, pairs} ->
          result = Map.new(pairs)

          if map_size(result) == length(pairs),
            do: {:ok, result},
            else: {:error, {:invalid_persistence_json, :duplicate_key}}

        error ->
          error
      end
    end
  end

  defp existing_atom(name) when is_binary(name) do
    {:ok, String.to_existing_atom(name)}
  rescue
    ArgumentError -> {:error, {:unknown_persistence_atom, name}}
  end

  defp existing_atom(value), do: {:error, {:invalid_persistence_atom, value}}

  defp exact_struct_fields(module, fields) do
    expected = module |> struct() |> Map.from_struct() |> Map.keys() |> MapSet.new()

    if MapSet.new(Map.keys(fields)) == expected,
      do: :ok,
      else: {:error, {:invalid_persistence_struct_fields, Atom.to_string(module)}}
  end

  defp preload_modules(_value, depth) when depth > @max_depth,
    do: {:error, {:persistence_json_limit, :depth}}

  defp preload_modules(%{@tag => "module", "name" => name} = value, _depth)
       when map_size(value) == 2 do
    with {:ok, _module} <- Jido.Persistence.Codec.load_module(name), do: :ok
  end

  defp preload_modules(value, depth) when is_map(value) do
    with :ok <- collection_size(map_size(value)) do
      value
      |> Map.values()
      |> Enum.reduce_while(:ok, fn item, :ok ->
        case preload_modules(item, depth + 1) do
          :ok -> {:cont, :ok}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    end
  end

  defp preload_modules(value, depth) when is_list(value) do
    with :ok <- collection_size(length(value)) do
      Enum.reduce_while(value, :ok, fn item, :ok ->
        case preload_modules(item, depth + 1) do
          :ok -> {:cont, :ok}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    end
  end

  defp preload_modules(_value, _depth), do: :ok

  defp map_values(values, depth, mapper) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, decoded} ->
      case mapper.(value, depth) do
        {:ok, item} -> {:cont, {:ok, [item | decoded]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
      error -> error
    end
  end

  defp collection_size(size) when size <= @max_collection_size, do: :ok
  defp collection_size(_size), do: {:error, {:persistence_json_limit, :collection}}
end
