defmodule Jido.Agent.Registry do
  @moduledoc """
  Maps stored identifiers to trusted Agent definition values.

  A Registry is a flat Map. Each identifier maps to one typed write entry or
  to one direct read alias. An alias cannot be a canonical write identifier.

      Jido.Agent.Registry.new!(%{
        "plugins/search" => {:plugin, MyApp.SearchPlugin},
        "actions/search" => {:action, MyApp.SearchAction},
        "actions/search-old" => {:alias, "actions/search"},
        "schemas/state" => {:schema, MyApp.State.schema()},
        "atoms/primary" => {:atom, :primary}
      })

  Stored text cannot create an atom or a module. The host must put each trusted
  value in the Registry before it can be resolved.

  A namespaced extension kind has this exact form:

      {:extension, trusted_extension_atom, trusted_local_kind_atom}

  Use `from_agent/1` only for temporary storage. Its generated identifiers are
  deterministic for the exact canonical Agent definition, but they are not
  durable application identifiers.
  """

  alias Jido.Error

  @maximum_entries 10_000
  @identifier_pattern ~r/\A[A-Za-z0-9][A-Za-z0-9._\/:@-]{0,254}\z/
  @core_kinds [:plugin, :action, :schema, :route_match, :extension, :atom]

  @type stable_id :: String.t()
  @type core_kind :: :plugin | :action | :schema | :route_match | :extension | :atom
  @type extension_kind :: {:extension, atom(), atom()}
  @type kind :: core_kind() | extension_kind()
  @type write_entry :: {kind(), term()}
  @type alias_entry :: {:alias, stable_id()}
  @type entry :: write_entry() | alias_entry()
  @type write_key :: {kind(), term()}
  @type t :: %__MODULE__{
          entries: %{stable_id() => entry()},
          write_ids: %{write_key() => stable_id()}
        }

  @enforce_keys [:entries, :write_ids]
  defstruct [:entries, :write_ids]

  @doc "Builds and validates a flat trusted-host Registry."
  @spec new(map() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{entries: entries}), do: new(entries)

  def new(%{} = entries) when map_size(entries) <= @maximum_entries do
    entries
    |> Enum.sort_by(fn {identifier, _entry} -> sort_key(identifier) end)
    |> Enum.reduce_while({:ok, %{}}, fn {identifier, entry}, {:ok, registry} ->
      with :ok <- validate_identifier(identifier),
           :ok <- validate_entry(entry) do
        {:cont, {:ok, Map.put(registry, identifier, entry)}}
      else
        {:error, validation_error} -> {:halt, {:error, validation_error}}
      end
    end)
    |> case do
      {:ok, normalized} -> build_registry(normalized)
      {:error, validation_error} -> {:error, validation_error}
    end
  end

  def new(%{} = entries) do
    error("Agent Registry exceeds its entry limit", %{
      entries: map_size(entries),
      maximum_entries: @maximum_entries
    })
  end

  def new(_entries), do: error("Agent Registry must be a map")

  @doc "Builds a Registry or raises its validation error."
  @spec new!(map() | t()) :: t() | no_return()
  def new!(entries) do
    case new(entries) do
      {:ok, registry} -> registry
      {:error, validation_error} -> raise validation_error
    end
  end

  @doc """
  Builds a temporary Registry from one executable Agent.

  This function checks executable contracts, but it does not run Agent work,
  mount a plugin, compile an extension, read application configuration, or add
  host default plugins.
  """
  @spec from_agent(Jido.Agent.t()) :: {:ok, t()} | {:error, Exception.t()}
  def from_agent(agent) do
    with {:ok, agent} <- Jido.Agent.validate_executable(agent),
         {:ok, entries} <- Jido.Agent.Registry.Deriver.entries(agent) do
      new(entries)
    end
  end

  @doc "Resolves one identifier with the exact required kind."
  @spec resolve(t(), stable_id(), kind()) :: {:ok, term()} | {:error, Exception.t()}
  def resolve(%__MODULE__{entries: entries}, identifier, kind) do
    with :ok <- validate_kind(kind),
         :ok <- validate_identifier(identifier) do
      case Map.fetch(entries, identifier) do
        {:ok, {:alias, write_identifier}} ->
          resolve_write_entry(entries, write_identifier, identifier, kind)

        {:ok, entry} ->
          resolve_entry(entry, identifier, kind)

        :error ->
          error("unknown Agent Registry identifier", %{identifier: identifier, kind: kind})
      end
    end
  end

  @doc "Returns the canonical write identifier for one trusted value."
  @spec identifier(t(), kind(), term()) :: {:ok, stable_id()} | {:error, Exception.t()}
  def identifier(%__MODULE__{write_ids: write_ids}, kind, value) do
    with :ok <- validate_kind(kind) do
      case Map.fetch(write_ids, {kind, value}) do
        {:ok, identifier} ->
          {:ok, identifier}

        :error ->
          error("Agent Registry has no identifier for the required value", %{kind: kind})
      end
    end
  end

  defp valid_identifier?(identifier) when is_binary(identifier) do
    byte_size(identifier) in 1..255 and Regex.match?(@identifier_pattern, identifier)
  end

  defp valid_identifier?(_identifier), do: false

  defp validate_identifier(identifier) do
    if valid_identifier?(identifier) do
      :ok
    else
      error("invalid Agent Registry identifier", %{
        identifier: bounded_identifier(identifier)
      })
    end
  end

  defp validate_kind(kind) when kind in @core_kinds, do: :ok

  defp validate_kind({:extension, extension, local_kind})
       when is_atom(extension) and extension not in [nil, true, false] and
              is_atom(local_kind) and local_kind not in [nil, true, false],
       do: :ok

  defp validate_kind(kind),
    do: error("invalid Agent Registry kind", %{kind: bounded_kind(kind)})

  defp validate_entry({:alias, identifier}), do: validate_identifier(identifier)

  defp validate_entry({kind, value}) do
    with :ok <- validate_kind(kind), do: validate_value(kind, value)
  end

  defp validate_entry(entry),
    do: error("invalid Agent Registry entry", %{entry: entry_type(entry)})

  defp validate_value(kind, module) when kind in [:plugin, :action, :extension] do
    if is_atom(module) and module not in [nil, true, false] do
      :ok
    else
      invalid_entry_value(kind, module)
    end
  end

  defp validate_value(:route_match, match) do
    if stable_external_unary_capture?(match) do
      :ok
    else
      invalid_entry_value(:route_match, match)
    end
  end

  defp validate_value(:atom, atom) when is_atom(atom), do: :ok
  defp validate_value(:atom, value), do: invalid_entry_value(:atom, value)
  defp validate_value(:schema, _schema), do: :ok
  defp validate_value({:extension, _extension, _local_kind}, _value), do: :ok

  defp invalid_entry_value(kind, value) do
    error("invalid Agent Registry entry", %{kind: kind, value: entry_type(value)})
  end

  defp stable_external_unary_capture?(function) when is_function(function, 1) do
    :erlang.fun_info(function, :type) == {:type, :external} and
      :erlang.fun_info(function, :env) == {:env, []}
  end

  defp stable_external_unary_capture?(_function), do: false

  defp bounded_identifier(identifier) when is_binary(identifier) and byte_size(identifier) <= 255,
    do: identifier

  defp bounded_identifier(identifier) when is_binary(identifier),
    do: %{type: :binary, bytes: byte_size(identifier)}

  defp bounded_identifier(identifier), do: %{type: entry_type(identifier)}

  defp bounded_kind({:extension, extension, local_kind}) do
    {:extension, entry_type(extension), entry_type(local_kind)}
  end

  defp bounded_kind(kind) when is_atom(kind), do: kind
  defp bounded_kind(kind), do: entry_type(kind)

  defp entry_type(value) when is_atom(value), do: :atom
  defp entry_type(value) when is_binary(value), do: :binary
  defp entry_type(value) when is_integer(value), do: :integer
  defp entry_type(value) when is_float(value), do: :float
  defp entry_type(value) when is_function(value), do: :function
  defp entry_type(value) when is_list(value), do: :list
  defp entry_type(value) when is_map(value), do: :map
  defp entry_type(value) when is_tuple(value), do: :tuple
  defp entry_type(_value), do: :other

  defp sort_key(identifier) when is_binary(identifier), do: {0, identifier}
  defp sort_key(identifier), do: {1, entry_type(identifier), :erlang.phash2(identifier)}

  defp build_registry(entries) do
    with :ok <- validate_aliases(entries),
         {:ok, write_ids} <- build_write_ids(entries) do
      {:ok, %__MODULE__{entries: entries, write_ids: write_ids}}
    end
  end

  defp validate_aliases(entries) do
    entries
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce_while(:ok, fn
      {identifier, {:alias, write_identifier}}, :ok ->
        case Map.fetch(entries, write_identifier) do
          {:ok, {:alias, _next_identifier}} ->
            {:halt,
             error("Agent Registry alias must refer directly to a write identifier", %{
               identifier: identifier,
               write_identifier: write_identifier
             })}

          {:ok, _write_entry} ->
            {:cont, :ok}

          :error ->
            {:halt,
             error("Agent Registry alias refers to an unknown write identifier", %{
               identifier: identifier,
               write_identifier: write_identifier
             })}
        end

      {_identifier, _write_entry}, :ok ->
        {:cont, :ok}
    end)
  end

  defp build_write_ids(entries) do
    entries
    |> Enum.reject(&match?({_identifier, {:alias, _write_identifier}}, &1))
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce_while({:ok, %{}}, fn {identifier, {kind, value}}, {:ok, write_ids} ->
      key = {kind, value}

      case Map.fetch(write_ids, key) do
        {:ok, existing_identifier} ->
          {:halt,
           error("Agent Registry has multiple write identifiers for the same value", %{
             kind: kind,
             identifiers: [existing_identifier, identifier]
           })}

        :error ->
          {:cont, {:ok, Map.put(write_ids, key, identifier)}}
      end
    end)
  end

  defp resolve_write_entry(entries, write_identifier, alias_identifier, kind) do
    case Map.fetch(entries, write_identifier) do
      {:ok, {:alias, _next_identifier}} ->
        error("Agent Registry alias must refer directly to a write identifier", %{
          identifier: alias_identifier,
          write_identifier: write_identifier
        })

      {:ok, entry} ->
        resolve_entry(entry, alias_identifier, kind)

      :error ->
        error("Agent Registry alias refers to an unknown write identifier", %{
          identifier: alias_identifier,
          write_identifier: write_identifier
        })
    end
  end

  defp resolve_entry({kind, value}, _identifier, kind), do: {:ok, value}

  defp resolve_entry({actual_kind, _value}, identifier, expected_kind) do
    error("Agent Registry identifier has the wrong entry kind", %{
      identifier: identifier,
      expected: expected_kind,
      actual: actual_kind
    })
  end

  defp error(message, details \\ %{}),
    do: {:error, Error.validation_error(message, details: details)}
end
