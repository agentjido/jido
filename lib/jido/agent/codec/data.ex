defmodule Jido.Agent.Codec.Data do
  @moduledoc false
  alias Jido.Agent.Authoring
  alias Jido.Agent.Codec.Registry

  def encode(value, registry, depth \\ 0)

  def encode(_value, _registry, depth) when depth > 100,
    do: Authoring.error("Authoring data is too deep")

  def encode(value, _registry, _depth)
      when is_nil(value) or is_boolean(value) or is_number(value), do: {:ok, value}

  def encode(value, _registry, _depth) when is_binary(value) do
    if String.valid?(value),
      do: {:ok, value},
      else: {:ok, %{"$type" => "binary", "value" => Base.encode64(value)}}
  end

  def encode(value, registry, _depth) when is_atom(value), do: reference(registry, :atom, value)

  def encode(value, registry, _depth) when is_struct(value),
    do: reference(registry, :value, value)

  def encode(value, registry, depth) when is_map(value) do
    with {:ok, entries} <-
           Authoring.traverse(Enum.sort(value), fn {key, item} ->
             with {:ok, key} <- encode(key, registry, depth + 1),
                  {:ok, item} <- encode(item, registry, depth + 1),
                  do: {:ok, [key, item]}
           end),
         do: {:ok, %{"$type" => "map", "entries" => entries}}
  end

  def encode(value, registry, depth) when is_tuple(value) do
    with {:ok, items} <- encode_list(Tuple.to_list(value), registry, depth),
         do: {:ok, %{"$type" => "tuple", "items" => items}}
  end

  def encode(value, registry, depth) when is_list(value), do: encode_list(value, registry, depth)

  def encode(_value, _registry, _depth),
    do: Authoring.error("Authoring data contains a runtime value")

  defp encode_list([], _registry, _depth), do: {:ok, []}

  defp encode_list([head | tail], registry, depth) do
    with {:ok, head} <- encode(head, registry, depth + 1),
         {:ok, tail} <- encode_list(tail, registry, depth),
         do: {:ok, [head | tail]}
  end

  defp encode_list(_tail, _registry, _depth),
    do: Authoring.error("Improper lists are not portable")

  defp reference(registry, kind, value) do
    with {:ok, id} <- Registry.identifier(registry, kind, value),
         do: {:ok, %{"$type" => Atom.to_string(kind), "id" => id}}
  end

  def decode(value, registry)

  def decode(value, _registry)
      when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value),
      do: {:ok, value}

  def decode(value, registry) when is_list(value),
    do: Authoring.traverse(value, &decode(&1, registry))

  def decode(%{"$type" => type, "id" => id} = value, registry)
      when map_size(value) == 2 and type in ["atom", "value"] do
    Registry.resolve(registry, id, if(type == "atom", do: :atom, else: :value))
  end

  def decode(%{"$type" => "binary", "value" => value} = data, _registry)
      when map_size(data) == 2 and is_binary(value) do
    case Base.decode64(value) do
      {:ok, value} -> {:ok, value}
      :error -> Authoring.error("Invalid base64 authoring value")
    end
  end

  def decode(%{"$type" => "tuple", "items" => items} = data, registry)
      when map_size(data) == 2 and is_list(items) do
    with {:ok, values} <- Authoring.traverse(items, &decode(&1, registry)),
         do: {:ok, List.to_tuple(values)}
  end

  def decode(%{"$type" => "map", "entries" => entries} = data, registry)
      when map_size(data) == 2 and is_list(entries) do
    with {:ok, pairs} <-
           Authoring.traverse(entries, fn
             [key, value] ->
               with {:ok, key} <- decode(key, registry),
                    {:ok, value} <- decode(value, registry),
                    do: {:ok, {key, value}}

             _ ->
               Authoring.error("Invalid map entry")
           end),
         decoded = Map.new(pairs),
         true <- length(pairs) == map_size(decoded) do
      {:ok, decoded}
    else
      false -> Authoring.error("Duplicate decoded map key")
      error -> error
    end
  end

  def decode(_value, _registry), do: Authoring.error("Invalid tagged authoring value")

  def check_document(value) do
    case check(value, 0, 0) do
      {:ok, nodes} when nodes > 100_000 ->
        Authoring.error("Authoring document exceeds its node limit")

      {:ok, _nodes} ->
        :ok

      error ->
        error
    end
  end

  defp check(_value, depth, nodes) when depth > 100 or nodes > 100_000,
    do: Authoring.error("Authoring document exceeds its size or depth limit")

  defp check(value, _depth, nodes) when is_nil(value) or is_boolean(value) or is_number(value),
    do: {:ok, nodes + 1}

  defp check(value, _depth, nodes) when is_binary(value) and byte_size(value) <= 1_048_576 do
    if String.valid?(value),
      do: {:ok, nodes + 1},
      else: Authoring.error("Document strings must be UTF-8")
  end

  defp check(value, depth, nodes)
       when is_map(value) and not is_struct(value) and map_size(value) <= 10_000 do
    if Enum.all?(Map.keys(value), &is_binary/1),
      do: check_map(:maps.iterator(value), depth + 1, nodes + 1),
      else: Authoring.error("Document object keys must be strings")
  end

  defp check(value, depth, nodes) when is_list(value),
    do: check_list(value, depth + 1, nodes + 1, 0, 10_000)

  defp check(_value, _depth, _nodes),
    do: Authoring.error("Invalid or oversized JSON document value")

  defp check_map(iterator, depth, nodes) do
    case :maps.next(iterator) do
      :none ->
        {:ok, nodes}

      {key, value, next} ->
        with {:ok, nodes} <- check(key, depth, nodes),
             {:ok, nodes} <- check(value, depth, nodes),
             do: check_map(next, depth, nodes)
    end
  end

  defp check_list([], _depth, nodes, _count, _limit), do: {:ok, nodes}

  defp check_list([head | tail], depth, nodes, count, limit) when count < limit do
    with {:ok, nodes} <- check(head, depth, nodes),
         do: check_list(tail, depth, nodes, count + 1, limit)
  end

  defp check_list(_tail, _depth, _nodes, _count, _limit),
    do: Authoring.error("Invalid or oversized document list")
end
