defmodule Jido.Authoring.Registry do
  @moduledoc """
  Stores trusted authoring entries and document codecs.

  References use `{stable_id, vsn}` tuples inside Elixir. Document codecs
  convert them to and from JSON objects at the storage boundary.
  """

  @maximum_entries 10_000
  @identifier_pattern ~r/\A[A-Za-z0-9][A-Za-z0-9._\/:@-]{0,254}\z/
  @map_schema %{
    id: "jido/schemas/map",
    kind: :schema,
    vsn: 1,
    target: Zoi.map(),
    provider: __MODULE__,
    name: "Map schema",
    description: "The default Jido map schema"
  }

  @type stable_id :: String.t()
  @type vsn :: pos_integer()
  @type kind :: atom()
  @type key :: {stable_id(), vsn()}
  @type entry :: {kind(), term()}
  @type manifest :: %{
          required(:id) => stable_id(),
          required(:kind) => kind(),
          required(:vsn) => vsn(),
          required(:target) => term(),
          optional(:name) => String.t() | nil,
          optional(:description) => String.t() | nil,
          optional(:provider) => module(),
          optional(:application) => atom() | nil
        }
  @type codec :: %{
          required(:type) => String.t(),
          required(:vsn) => vsn(),
          required(:module) => module(),
          optional(:encoder) => module() | nil
        }
  @type t :: %__MODULE__{
          entries: %{key() => entry()},
          references: %{{kind(), term()} => key()},
          manifests: [manifest()],
          codecs: %{{String.t(), pos_integer()} => module()},
          encoders: %{module() => module()},
          revision: String.t() | nil
        }

  @enforce_keys [:entries, :references, :manifests, :codecs, :encoders, :revision]
  defstruct @enforce_keys

  defmodule Error do
    @moduledoc "An invalid trusted authoring Registry or Registry operation."
    use Splode.Error,
      class: :invalid,
      fields: [message: "Invalid authoring Registry", details: %{}]

    @type t :: %__MODULE__{message: String.t(), details: map()}
  end

  @doc "Builds and validates a trusted typed-reference map."
  @spec new(%{optional(key()) => entry()} | t()) :: {:ok, t()} | {:error, Error.t()}
  def new(%__MODULE__{} = registry), do: {:ok, registry}

  def new(entries)
      when is_map(entries) and not is_struct(entries) and map_size(entries) <= @maximum_entries do
    with {:ok, entries} <- validate_entries(entries),
         {:ok, references} <- build_references(entries) do
      {:ok,
       %__MODULE__{
         entries: entries,
         references: references,
         manifests: [],
         codecs: %{},
         encoders: %{},
         revision: nil
       }}
    end
  end

  def new(entries) when is_map(entries) and not is_struct(entries) do
    error("authoring Registry exceeds its entry limit", %{
      entries: map_size(entries),
      maximum_entries: @maximum_entries
    })
  end

  def new(_entries), do: error("authoring Registry must be a map")

  @doc false
  @spec new_discovered([manifest()], [codec()]) :: {:ok, t()} | {:error, term()}
  def new_discovered(manifests, codecs) do
    manifests =
      [@map_schema | manifests]
      |> Enum.sort_by(&{&1.id, &1.vsn, Atom.to_string(&1.kind), Atom.to_string(&1.provider)})

    codecs = Enum.sort_by(codecs, &{&1.type, &1.vsn, Atom.to_string(&1.module)})
    entries = Map.new(manifests, &{{&1.id, &1.vsn}, {&1.kind, &1.target}})

    with :ok <- unique(manifests, &{&1.id, &1.vsn}, :duplicate_authoring_reference),
         :ok <- unique(manifests, &{&1.kind, &1.target}, :duplicate_authoring_target),
         :ok <- unique(codecs, &{&1.type, &1.vsn}, :duplicate_authoring_codec),
         :ok <- unique_encoders(codecs),
         {:ok, registry} <- new(entries) do
      {:ok,
       %{
         registry
         | manifests: manifests,
           codecs: Map.new(codecs, &{{&1.type, &1.vsn}, &1.module}),
           encoders:
             codecs
             |> Enum.reject(&is_nil(Map.get(&1, :encoder)))
             |> Map.new(&{&1.encoder, &1.module}),
           revision: revision(manifests, codecs)
       }}
    end
  end

  @doc "Builds a Registry or raises its validation error."
  @spec new!(%{optional(key()) => entry()} | t()) :: t() | no_return()
  def new!(entries) do
    case new(entries) do
      {:ok, registry} -> registry
      {:error, exception} -> raise exception
    end
  end

  @doc "Resolves one exact reference of the required kind."
  @spec resolve(t(), key(), kind() | [kind()]) :: {:ok, term()} | {:error, Error.t()}
  def resolve(%__MODULE__{entries: entries}, reference, kinds) when is_list(kinds) do
    with :ok <- validate_kinds(kinds),
         do: resolve_one(entries, reference, kinds, kinds, List.last(kinds))
  end

  def resolve(%__MODULE__{entries: entries}, reference, kind)
      when is_atom(kind) and kind not in [nil, true, false, :alias] do
    resolve_one(entries, reference, [kind], kind, kind)
  end

  def resolve(%__MODULE__{}, reference, kind),
    do: error("invalid authoring Registry reference", %{reference: type(reference), kind: kind})

  @doc "Finds the canonical reference for one typed value."
  @spec reference(t(), kind() | [kind()], term()) :: {:ok, key()} | {:error, Error.t()}
  def reference(%__MODULE__{references: references}, kinds, value) when is_list(kinds) do
    with :ok <- validate_kinds(kinds) do
      reference_one(references, kinds, value, %{kinds: kinds})
    end
  end

  def reference(%__MODULE__{references: references}, kind, value)
      when is_atom(kind) and kind not in [nil, true, false, :alias] do
    reference_one(references, [kind], value, %{kind: kind})
  end

  def reference(%__MODULE__{}, kind, _value),
    do: error("invalid authoring Registry kind", %{kind: kind})

  @doc "Encodes the canonical reference for one typed value as JSON-safe data."
  @spec encode_reference(t(), kind() | [kind()], term()) ::
          {:ok, %{required(String.t()) => term()}} | {:error, Error.t()}
  def encode_reference(%__MODULE__{} = registry, kinds, value) do
    with {:ok, {id, vsn}} <- reference(registry, kinds, value),
         do: {:ok, %{"id" => id, "vsn" => vsn}}
  end

  @doc "Decodes JSON-safe reference data and resolves its typed value."
  @spec decode_reference(t(), term(), kind() | [kind()]) ::
          {:ok, term()} | {:error, Error.t()}
  def decode_reference(%__MODULE__{} = registry, document, kinds) do
    with {:ok, reference} <- parse_reference(document),
         do: resolve(registry, reference, kinds)
  end

  @doc "Returns a manifest by identifier and version."
  @spec get(t(), stable_id(), vsn()) :: manifest() | nil
  def get(%__MODULE__{manifests: manifests}, id, vsn),
    do: Enum.find(manifests, &(&1.id == id and &1.vsn == vsn))

  @doc "Returns a manifest by kind, identifier, and version."
  @spec get(t(), kind(), stable_id(), vsn()) :: manifest() | nil
  def get(registry, kind, id, vsn) do
    case get(registry, id, vsn) do
      %{kind: ^kind} = manifest -> manifest
      _other -> nil
    end
  end

  @doc "Returns a manifest by kind and target."
  @spec get_by_target(t(), kind(), term()) :: manifest() | nil
  def get_by_target(%__MODULE__{manifests: manifests}, kind, target),
    do: Enum.find(manifests, &(&1.kind == kind and &1.target == target))

  @doc "Lists all manifests."
  @spec list(t()) :: [manifest()]
  def list(%__MODULE__{manifests: manifests}), do: manifests

  @doc "Lists manifests of one kind."
  @spec list(t(), kind()) :: [manifest()]
  def list(%__MODULE__{manifests: manifests}, kind)
      when is_atom(kind) and kind not in [nil, true, false, :alias],
      do: Enum.filter(manifests, &(&1.kind == kind))

  @doc false
  @spec encoder(t(), term()) :: {:ok, module()} | {:error, :unknown_encoder}
  def encoder(%__MODULE__{encoders: encoders}, %{__struct__: struct}) do
    case Map.fetch(encoders, struct) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unknown_encoder}
    end
  end

  def encoder(%__MODULE__{}, _value), do: {:error, :unknown_encoder}

  @doc false
  @spec codec(t(), String.t(), vsn()) :: {:ok, module()} | {:error, :unknown_codec}
  def codec(%__MODULE__{codecs: codecs}, type, vsn) do
    case Map.fetch(codecs, {type, vsn}) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unknown_codec}
    end
  end

  @doc false
  @spec codec_vsns(t(), String.t()) :: [vsn()]
  def codec_vsns(%__MODULE__{codecs: codecs}, type) do
    codecs
    |> Map.keys()
    |> Enum.flat_map(fn {entry_type, vsn} -> if entry_type == type, do: [vsn], else: [] end)
    |> Enum.sort()
  end

  @doc false
  @spec validate_reference(term()) :: {:ok, key()} | {:error, Error.t()}
  def validate_reference({id, vsn}) do
    with :ok <- validate_identifier(id),
         :ok <- validate_vsn(vsn),
         do: {:ok, {id, vsn}}
  end

  def validate_reference(reference),
    do: error("invalid authoring Registry reference", %{reference: type(reference)})

  @doc false
  @spec validate_identifier(term()) :: :ok | {:error, Error.t()}
  def validate_identifier(id) do
    if is_binary(id) and byte_size(id) in 1..255 and Regex.match?(@identifier_pattern, id),
      do: :ok,
      else: error("invalid authoring Registry identifier", %{identifier: type(id), field: "id"})
  end

  @doc false
  @spec validate_vsn(term()) :: :ok | {:error, Error.t()}
  def validate_vsn(vsn) when is_integer(vsn) and vsn > 0, do: :ok
  def validate_vsn(vsn), do: error("invalid authoring Registry vsn", %{vsn: vsn, field: "vsn"})

  defp parse_reference(%{"id" => id, "vsn" => vsn} = reference)
       when map_size(reference) == 2,
       do: {:ok, {id, vsn}}

  defp parse_reference(%{} = reference) when not is_struct(reference) do
    fields = Map.keys(reference)

    field =
      case Enum.sort(fields -- ["id", "vsn"]) do
        [unknown | _rest] -> unknown
        [] -> if("id" in fields, do: "vsn", else: "id")
      end

    error("authoring Registry reference must contain only id and vsn", %{field: field})
  end

  defp parse_reference(_reference),
    do: error("authoring Registry reference must contain only id and vsn")

  defp validate_kinds([]), do: error("invalid authoring Registry kinds", %{kinds: []})

  defp validate_kinds(kinds) do
    if Enum.all?(kinds, &(is_atom(&1) and &1 not in [nil, true, false, :alias])),
      do: :ok,
      else: error("invalid authoring Registry kinds", %{kinds: kinds})
  end

  defp resolve_one(entries, reference, kinds, expected, missing_kind) do
    with {:ok, {id, vsn} = key} <- validate_reference(reference) do
      case Map.fetch(entries, key) do
        {:ok, {kind, value}} ->
          if kind in kinds do
            {:ok, value}
          else
            error("authoring Registry reference has the wrong entry kind", %{
              identifier: id,
              vsn: vsn,
              expected: expected,
              actual: kind,
              field: "id"
            })
          end

        :error ->
          missing_reference(entries, id, vsn, missing_kind)
      end
    end
  end

  defp reference_one(references, kinds, value, details) do
    case Enum.find_value(kinds, &Map.get(references, {&1, value})) do
      nil -> error("authoring Registry has no reference for the required value", details)
      reference -> {:ok, reference}
    end
  end

  defp validate_entries(entries) do
    Enum.reduce_while(entries, {:ok, %{}}, fn {key, entry}, {:ok, valid} ->
      with {:ok, key} <- validate_reference(key),
           {:ok, entry} <- validate_entry(entry) do
        {:cont, {:ok, Map.put(valid, key, entry)}}
      else
        {:error, %Error{}} = error -> {:halt, error}
      end
    end)
  end

  defp validate_entry({kind, value})
       when is_atom(kind) and kind not in [nil, true, false, :alias],
       do: {:ok, {kind, value}}

  defp validate_entry(entry), do: error("invalid authoring Registry entry", %{entry: type(entry)})

  defp build_references(entries) do
    Enum.reduce_while(entries, {:ok, %{}}, fn {reference, {kind, value}}, {:ok, refs} ->
      case Map.fetch(refs, {kind, value}) do
        {:ok, existing} ->
          {:halt,
           error("authoring Registry has multiple references for the same value", %{
             kind: kind,
             references: [existing, reference]
           })}

        :error ->
          {:cont, {:ok, Map.put(refs, {kind, value}, reference)}}
      end
    end)
  end

  defp missing_reference(entries, id, vsn, kind) do
    supported =
      entries
      |> Map.keys()
      |> Enum.flat_map(fn {entry_id, entry_vsn} ->
        if entry_id == id, do: [entry_vsn], else: []
      end)
      |> Enum.sort()

    if supported == [] do
      error("unknown authoring Registry reference", %{
        identifier: id,
        vsn: vsn,
        kind: kind,
        field: "id"
      })
    else
      error("authoring Registry reference has unsupported vsn", %{
        identifier: id,
        vsn: vsn,
        kind: kind,
        supported_vsns: supported,
        field: "vsn"
      })
    end
  end

  defp unique(values, key, tag) do
    duplicate =
      values
      |> Enum.group_by(key)
      |> Enum.find_value(fn {entry_key, grouped} -> if length(grouped) > 1, do: entry_key end)

    if duplicate, do: {:error, {tag, duplicate}}, else: :ok
  end

  defp unique_encoders(codecs) do
    codecs
    |> Enum.reject(&is_nil(Map.get(&1, :encoder)))
    |> unique(& &1.encoder, :duplicate_authoring_encoder)
  end

  defp revision(manifests, codecs) do
    {manifests, codecs}
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end

  defp type(value) when is_atom(value), do: :atom
  defp type(value) when is_binary(value), do: :binary
  defp type(value) when is_integer(value), do: :integer
  defp type(value) when is_list(value), do: :list
  defp type(value) when is_map(value), do: :map
  defp type(value) when is_tuple(value), do: :tuple
  defp type(_value), do: :other

  defp error(message, details \\ %{}),
    do: {:error, Error.exception(message: message, details: details)}
end
