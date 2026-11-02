defmodule Jido.Signal.Catalog do
  @moduledoc """
  Selects and validates explicitly registered Signal definitions.

  A catalog is an immutable value. `new/1` captures the type, `dataschema`,
  and Zoi data schema from each supplied `use Jido.Signal` module. It matches
  exact `{type, dataschema}` pairs. A definition without `dataschema` matches
  only Signals without `dataschema`. Duplicate pairs are errors, even when
  the same module appears twice. Different schema versions can share a type.

  Create catalogs with `new/1` or `new!/1`. Their internal representation is
  opaque. Registration validates one snapshot of each module's existing
  definition metadata using the Signal envelope's type and schema URI rules.

  `decode/3` uses the existing Signal codec and serialization boundary.
  `validate/2` checks an existing Signal envelope, its flat context, and its
  selected data schema. Neither function calls a constructor or generates an
  ID. The supplied ID, time, source, subject, and valid context are preserved.
  Zoi can apply data defaults and transforms declared by the definition.
  When data changes, the existing codec keeps its presence and Base64 flags
  consistent with the returned value.

  Data keys follow the definition's Zoi schema. The catalog does not enable
  coercion, convert arbitrary keys to atoms, or select modules from input.
  Use string-key schemas for JSON data. See the [catalog guide](catalog.md).

  ## Examples

      catalog = Jido.Signal.Catalog.new!([MyApp.MessageReceived, MyApp.TemperatureMeasured])
      {:ok, signal} = Jido.Signal.Catalog.decode(catalog, json)
      {:ok, signal} = Jido.Signal.Catalog.validate(catalog, signal)

  ## Errors

  All failures return `{:error, %Jido.Signal.Error.InvalidInputError{}}`.
  The `details.code` field is one of:

  * `:invalid_definitions` — registration input or metadata is invalid, or a metadata callback failed.
  * `:duplicate_definition` — two registrations have the same exact pair.
  * `:invalid_input` — expected a catalog, Signal, map, or binary.
  * `:invalid_options` — options were supplied for a map.
  * `:decode_failed` — the wire format or envelope is invalid, or is a batch.
  * `:invalid_envelope` — an existing Signal or its context is invalid.
  * `:unknown_type` — the type has no registered definition.
  * `:unknown_dataschema` — the type is known but the schema identity is not.
  * `:invalid_data` — the selected Zoi schema rejected the data.
  * `:validation_failed` — a trusted Zoi callback raised, threw, or exited.

  `details.reason` retains codec/serialization errors or Zoi errors where
  applicable. Lookup and data errors include `type` and `dataschema`.
  Data errors also include the selected `definition` module. Duplicate errors
  include both modules in registration order under `definitions`.
  Metadata errors include the supplied `definition` module. Callback and
  codec faults retain `{kind, value}` under `reason`.

  A catalog does not migrate data, fetch schemas, authorize operations, or
  execute commands. Registered schemas and their callbacks are trusted code.
  """

  alias Jido.Signal
  alias Jido.Signal.Context
  alias Jido.Signal.Error
  alias Jido.Signal.Error.InvalidInputError
  alias Jido.Signal.Serialization

  @definitions_schema Zoi.list(Zoi.atom() |> Zoi.refine({__MODULE__, :validate_definition, []}))
  @type_schema Keyword.fetch!(Signal.schema().fields, :type)
  @dataschema_schema Keyword.fetch!(Signal.schema().fields, :dataschema)
  @data_schema Zoi.any() |> Zoi.refine({Signal, :validate_definition_schema, []})
  @definition_schema Zoi.object(%{
                       type: @type_schema,
                       dataschema: @dataschema_schema,
                       schema: @data_schema
                     })
  @catalog_schema Zoi.struct(__MODULE__, %{
                    definitions:
                      Zoi.map(
                        @type_schema,
                        Zoi.map(@dataschema_schema, Zoi.tuple({Zoi.atom(), @data_schema}))
                      )
                  })

  @typedoc "An immutable index of exact Signal type and schema identities."
  @opaque t :: unquote(Zoi.type_spec(@catalog_schema))
  @enforce_keys Zoi.Struct.enforce_keys(@catalog_schema)
  defstruct Zoi.Struct.struct_fields(@catalog_schema)

  @error_messages %{
    invalid_definitions: "Expected a list of Signal definition modules",
    duplicate_definition: "Signal definition pair is already registered",
    invalid_input: "Invalid catalog input",
    invalid_options: "Decode options apply only to binary input",
    decode_failed: "Signal wire decoding failed",
    invalid_envelope: "Invalid Signal envelope or context",
    unknown_type: "Signal type is not registered",
    unknown_dataschema: "Signal schema identity is not registered for this type",
    invalid_data: "Signal data failed definition validation",
    validation_failed: "Signal definition validation failed"
  }

  @doc """
  Builds a catalog from an explicit list of custom Signal modules.

  An empty list is valid. All duplicate `{type, dataschema}` pairs are rejected.
  The supplied modules are trusted application configuration.
  """
  @spec new([module()]) :: {:ok, t()} | {:error, %InvalidInputError{}}
  def new(modules) when is_list(modules) and is_integer(length(modules)) do
    case Zoi.parse(@definitions_schema, modules) do
      {:ok, modules} -> build(modules)
      {:error, errors} -> error(:invalid_definitions, %{reason: errors})
    end
  end

  def new(_modules),
    do: error(:invalid_definitions, %{reason: [Zoi.Error.invalid_type(:list)]})

  @doc "Builds a catalog, or raises `Jido.Signal.Error.InvalidInputError`."
  @spec new!([module()]) :: t() | no_return()
  def new!(modules) do
    case new(modules) do
      {:ok, catalog} -> catalog
      {:error, error} -> raise error
    end
  end

  @doc """
  Decodes one canonical wire map or binary and validates its definition.

  Binary options are forwarded to `Jido.Signal.Serialization.deserialize/2`.
  JSON is the default. The configured payload limit applies to binary input.
  Maps must be complete wire envelopes; constructor defaults are not added.
  Maps accept no options. Lists, JSON batches, and Signal structs are rejected.
  Use `validate/2` for an existing Signal.
  """
  @spec decode(t(), map() | binary(), keyword()) ::
          {:ok, Signal.t()} | {:error, %InvalidInputError{}}
  def decode(catalog, wire_value, opts \\ [])

  def decode(%__MODULE__{definitions: definitions} = catalog, wire_value, opts)
      when is_map(definitions) do
    with {:ok, signal} <- decode_wire(wire_value, opts) do
      validate_definition_data(catalog, signal)
    end
  end

  def decode(_catalog, _wire_value, _opts), do: error(:invalid_input, %{field: :catalog})

  @doc """
  Revalidates an existing Signal without replacing its identity or metadata.

  The envelope and flat context are checked before exact definition lookup.
  The selected Zoi schema validates data using the same rules as construction.
  Data defaults and transforms can change the returned data value.
  """
  @spec validate(t(), Signal.t()) :: {:ok, Signal.t()} | {:error, %InvalidInputError{}}
  def validate(%__MODULE__{definitions: definitions} = catalog, %Signal{} = signal)
      when is_map(definitions) do
    with {:ok, signal} <- validate_envelope(signal) do
      validate_definition_data(catalog, signal)
    end
  end

  def validate(%__MODULE__{definitions: definitions}, _signal) when is_map(definitions),
    do: error(:invalid_input, %{field: :signal})

  def validate(_catalog, _signal), do: error(:invalid_input, %{field: :catalog})

  @doc false
  @spec validate_definition(term(), keyword()) :: :ok | {:error, String.t()}
  def validate_definition(module, _opts) do
    if Signal.defined?(module) do
      :ok
    else
      {:error, "must be a module defined with use Jido.Signal"}
    end
  end

  defp build(modules) do
    Enum.reduce_while(modules, {:ok, %__MODULE__{definitions: %{}}}, fn module, {:ok, catalog} ->
      with {:ok, definition} <- read_definition(module),
           {:ok, catalog} <- register(catalog, module, definition) do
        {:cont, {:ok, catalog}}
      else
        {:error, _error} = error -> {:halt, error}
      end
    end)
  end

  defp read_definition(module) do
    case Zoi.parse(@definition_schema, module.__signal_definition__()) do
      {:ok, definition} -> {:ok, definition}
      {:error, reason} -> registration_error(module, reason)
    end
  rescue
    exception -> registration_error(module, {:exception, exception})
  catch
    kind, reason -> registration_error(module, {kind, reason})
  end

  defp registration_error(module, reason),
    do: error(:invalid_definitions, %{definition: module, reason: reason})

  defp register(catalog, module, definition) do
    type = definition.type
    dataschema = Map.get(definition, :dataschema)
    versions = Map.get(catalog.definitions, type, %{})

    case Map.fetch(versions, dataschema) do
      {:ok, {existing, _schema}} ->
        error(:duplicate_definition, %{
          type: type,
          dataschema: dataschema,
          definitions: [existing, module]
        })

      :error ->
        versions = Map.put(versions, dataschema, {module, definition.schema})
        {:ok, %{catalog | definitions: Map.put(catalog.definitions, type, versions)}}
    end
  end

  defp decode_wire(binary, opts) when is_binary(binary) do
    binary |> Serialization.deserialize(opts) |> decode_result()
  end

  defp decode_wire(map, []) when is_map(map) and not is_struct(map) do
    map |> Signal.from_map() |> decode_result()
  rescue
    exception -> error(:decode_failed, %{reason: {:exception, exception}})
  catch
    kind, reason -> error(:decode_failed, %{reason: {kind, reason}})
  end

  defp decode_wire(map, _opts) when is_map(map) and not is_struct(map),
    do: error(:invalid_options, %{field: :options})

  defp decode_wire(_wire_value, _opts), do: error(:invalid_input, %{field: :wire_value})

  defp decode_result({:ok, %Signal{} = signal}), do: {:ok, signal}

  defp decode_result({:ok, _batch}),
    do: error(:decode_failed, %{reason: {:invalid_wire_data, "expected one Signal"}})

  defp decode_result({:error, reason}), do: error(:decode_failed, %{reason: reason})

  defp validate_definition_data(catalog, signal) do
    with {:ok, {module, schema}} <- lookup(catalog, signal),
         {:ok, data} <- validate_data(schema, signal, module) do
      normalize_data(signal, data)
    end
  end

  defp normalize_data(%Signal{data: data} = signal, data), do: {:ok, signal}

  defp normalize_data(signal, data) do
    # The codec owns data presence and Base64 flags. Reuse it after a Zoi
    # default or transform changes data, without generating a new fact ID.
    case signal |> Map.put(:data, data) |> Signal.to_map() |> Signal.from_map() do
      {:ok, signal} -> {:ok, signal}
      {:error, reason} -> error(:invalid_envelope, %{reason: reason})
    end
  end

  defp validate_envelope(signal) do
    with {:ok, context} <- Context.normalize(signal.extensions),
         {:ok, signal} <- Zoi.parse(Signal.schema(), %{signal | extensions: context}) do
      {:ok, signal}
    else
      {:error, reason} -> error(:invalid_envelope, %{reason: reason})
    end
  end

  defp lookup(catalog, signal) do
    case Map.fetch(catalog.definitions, signal.type) do
      {:ok, versions} when is_map(versions) -> lookup_version(versions, signal)
      :error -> error(:unknown_type, identity(signal))
      _invalid -> error(:invalid_input, %{field: :catalog})
    end
  end

  defp lookup_version(versions, signal) do
    case Map.fetch(versions, signal.dataschema) do
      {:ok, {module, schema} = definition} when is_atom(module) ->
        if Signal.validate_definition_schema(schema, []) == :ok,
          do: {:ok, definition},
          else: error(:invalid_input, %{field: :catalog})

      :error ->
        error(:unknown_dataschema, identity(signal))

      _invalid ->
        error(:invalid_input, %{field: :catalog})
    end
  end

  defp validate_data(schema, signal, module) do
    case Zoi.parse(schema, signal.data) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> data_error(:invalid_data, signal, module, reason)
    end
  rescue
    exception -> data_error(:validation_failed, signal, module, {:exception, exception})
  catch
    kind, reason -> data_error(:validation_failed, signal, module, {kind, reason})
  end

  defp data_error(code, signal, module, reason) do
    error(code, Map.merge(identity(signal), %{definition: module, reason: reason}))
  end

  defp identity(signal), do: %{type: signal.type, dataschema: signal.dataschema}

  defp error(code, details) do
    {:error,
     Error.validation_error(Map.fetch!(@error_messages, code), Map.put(details, :code, code))}
  end
end
