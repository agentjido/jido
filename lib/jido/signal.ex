defmodule Jido.Signal do
  alias Jido.Joi

  @moduledoc """
  Defines the Jido event envelope.

  A Signal uses the CloudEvents 1.0 context attributes. Jido generates UUID7
  values for new Signal IDs. It does not infer the event source, event time, or
  data content type.

  The required attributes are `specversion`, `id`, `source`, and `type`.
  `specversion` is always `"1.0"` on output. A legacy `"1.0.2"` value is
  accepted on input and is normalized to `"1.0"`.

  Extension context attributes are optional flat metadata. Their names and
  values follow the CloudEvents rules. Put domain fields in `data` and validate
  them with a custom Signal module.

  The canonical map keeps Signal data in `data`. It encodes non-UTF-8 binary
  data as raw bytes in the CloudEvents `data_base64` member. JSON serialization
  accepts only JSON values in `data`.

  ## Examples

      {:ok, signal} =
        Jido.Signal.new("user.created", %{user_id: "123"}, source: "/accounts")

      signal.specversion
      #=> "1.0"

      Jido.Id.uuid7?(signal.id)
      #=> true

  ## Custom Signal modules

      defmodule MyApp.UserCreated do
        alias Jido.Joi

        use Jido.Signal,
          type: "user.created",
          default_source: "/accounts",
          schema:
            Joi.object(%{
              user_id: Joi.string()
            })
      end

  Custom schemas must be static module data. Joi refinements, transforms, and
  other callbacks must use named `{Module, :function, args}` MFA values.
  Anonymous functions and lazy schemas are not accepted.

  A custom schema can accept any Signal data value. Its `validate_data/1` and
  `new/2` functions return Joi validation errors directly. Its `new!/2`
  function raises the Joi parse exception when data validation fails.

  `Jido.Signal.defined?/1` recognizes these modules. `Jido.Signal.Router`
  accepts them as route paths and uses `type/0` as the exact path.

  The definition owns `type`, `dataschema`, and validated `data`. Constructor
  options cannot change these values, including an absent `dataschema`.
  Use a separate definition for each schema identity. Other envelope options
  can override configured defaults. `Jido.Signal.Catalog` selects definitions
  by exact type and schema identity when it decodes or validates a Signal.
  """

  @default_data_schema Joi.any()

  @core_names ~w[
    specversion id source type subject time
    datacontenttype dataschema data data_base64
  ]
  @constructor_names ["extensions" | @core_names]
  @legacy_wire_version_key "jido_schema_version"
  @legacy_wire_versions [1, 2]
  @extension_name_pattern ~r/\A[a-z][a-z0-9]{0,19}\z/
  @extension_min_integer -2_147_483_648
  @extension_max_integer 2_147_483_647

  @media_type_pattern ~r{\A[!#$%&'*+.^_`|~0-9A-Za-z-]+/[!#$%&'*+.^_`|~0-9A-Za-z-]+(?:[ \t]*;[ \t]*[!#$%&'*+.^_`|~0-9A-Za-z-]+[ \t]*=[ \t]*(?:[!#$%&'*+.^_`|~0-9A-Za-z-]+|"(?:[\x20-\x21\x23-\x5B\x5D-\x7E]|\\[\x20-\x7E])*"))*\z}
  @uri_reference_pattern ~r"\A(?:[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=]|%[0-9A-Fa-f]{2})*\z"
  @rfc3339_pattern ~r/\A([0-9]{4}-[0-9]{2}-[0-9]{2}[Tt ][0-9]{2}:[0-9]{2}:)([0-9]{2})(\.[0-9]+)?([Zz]|[+-](?:[01][0-9]|2[0-3]):[0-5][0-9])\z/

  @definition_defaults %{
    datacontenttype: nil,
    dataschema: nil,
    default_source: nil,
    schema: @default_data_schema
  }

  @definition_schema Joi.keyword(
                       [
                         type:
                           Joi.string()
                           |> Joi.min(1)
                           |> Joi.refine({__MODULE__, :validate_utf8_string, []})
                           |> Joi.required(),
                         default_source:
                           Joi.string()
                           |> Joi.min(1)
                           |> Joi.refine({__MODULE__, :validate_uri_reference, []}),
                         datacontenttype:
                           Joi.string()
                           |> Joi.min(1)
                           |> Joi.refine({__MODULE__, :validate_media_type, []}),
                         dataschema:
                           Joi.string()
                           |> Joi.min(1)
                           |> Joi.refine({__MODULE__, :validate_absolute_uri, []}),
                         schema:
                           Joi.any()
                           |> Joi.refine({__MODULE__, :validate_definition_schema, []})
                           |> Joi.default(@default_data_schema)
                       ],
                       unrecognized_keys: :error
                     )

  @signal_schema Joi.struct(
                   __MODULE__,
                   %{
                     id:
                       Joi.string()
                       |> Joi.min(1)
                       |> Joi.refine({__MODULE__, :validate_utf8_string, []}),
                     source:
                       Joi.string()
                       |> Joi.min(1)
                       |> Joi.refine({__MODULE__, :validate_uri_reference, []}),
                     type:
                       Joi.string()
                       |> Joi.min(1)
                       |> Joi.refine({__MODULE__, :validate_utf8_string, []}),
                     specversion: Joi.default(Joi.literal("1.0"), "1.0") |> Joi.optional(),
                     subject:
                       Joi.string()
                       |> Joi.min(1)
                       |> Joi.refine({__MODULE__, :validate_utf8_string, []})
                       |> Joi.nullable()
                       |> Joi.optional(),
                     time:
                       Joi.string()
                       |> Joi.refine({__MODULE__, :validate_rfc3339, []})
                       |> Joi.nullable()
                       |> Joi.optional(),
                     datacontenttype:
                       Joi.string()
                       |> Joi.min(1)
                       |> Joi.refine({__MODULE__, :validate_media_type, []})
                       |> Joi.nullable()
                       |> Joi.optional(),
                     dataschema:
                       Joi.string()
                       |> Joi.refine({__MODULE__, :validate_absolute_uri, []})
                       |> Joi.nullable()
                       |> Joi.optional(),
                     data: Joi.any() |> Joi.optional(),
                     data_present?: Joi.boolean() |> Joi.default(false) |> Joi.optional(),
                     data_base64?: Joi.boolean() |> Joi.default(false) |> Joi.optional(),
                     extensions: Joi.default(Joi.map(), %{}) |> Joi.optional()
                   }
                 )

  @type t :: unquote(Joi.type_spec(@signal_schema))
  @enforce_keys Joi.enforce_keys(@signal_schema)
  defstruct Joi.struct_fields(@signal_schema)

  @doc "Returns the Joi schema for the core Signal envelope."
  @spec schema() :: Joi.schema()
  def schema, do: @signal_schema

  @doc """
  Returns true when `module` was defined with `use Jido.Signal`.

  Does not create atoms. An atom that is not a loaded Signal module returns
  false.
  """
  @spec defined?(term()) :: boolean()
  def defined?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :__signal_definition__, 0) and
      function_exported?(module, :type, 0)
  end

  def defined?(_module), do: false

  @doc "Defines a custom Signal module with a static Joi data schema."
  defmacro __using__(opts_ast) do
    quote location: :keep do
      @signal_definition Jido.Signal.__compile_definition__(unquote(opts_ast), __ENV__)

      @doc false
      @spec __signal_definition__() :: map()
      def __signal_definition__, do: @signal_definition

      @doc "Returns the Signal type."
      @spec type() :: String.t()
      def type, do: @signal_definition[:type]

      @doc "Returns the default source, if one is configured."
      @spec default_source() :: String.t() | nil
      def default_source, do: @signal_definition[:default_source]

      @doc "Returns the configured data content type."
      @spec datacontenttype() :: String.t() | nil
      def datacontenttype, do: @signal_definition[:datacontenttype]

      @doc "Returns the configured data schema URI."
      @spec dataschema() :: String.t() | nil
      def dataschema, do: @signal_definition[:dataschema]

      @doc "Returns the static Joi data schema."
      @spec schema() :: Joi.schema()
      def schema, do: @signal_definition[:schema]

      @doc "Validates data with the static Joi schema."
      @spec validate_data(term()) :: Joi.result()
      def validate_data(data), do: Joi.parse(schema(), data)

      @doc """
      Creates a Signal with the definition's type, dataschema, and validated data.

      Options cannot override these values. A definition without dataschema
      keeps it absent. Other envelope attributes can be supplied in options.
      """
      @spec new(term(), keyword() | map()) ::
              {:ok, Jido.Signal.t()} | {:error, [Joi.error()] | String.t()}
      def new(data \\ %{}, opts \\ []) do
        defaults =
          %{
            "source" => default_source(),
            "datacontenttype" => datacontenttype()
          }
          |> Map.reject(fn {_key, value} -> is_nil(value) end)

        with {:ok, validated_data} <- validate_data(data),
             {:ok, attrs} <- Jido.Signal.__normalize_definition_attrs__(opts, defaults) do
          attrs
          |> Map.put("type", type())
          |> Map.put("dataschema", dataschema())
          |> Map.put("data", validated_data)
          |> Jido.Signal.new()
        end
      end

      @doc "Creates a Signal and raises when the data or envelope is invalid."
      @spec new!(term(), keyword() | map()) :: Jido.Signal.t() | no_return()
      def new!(data \\ %{}, opts \\ []) do
        case new(data, opts) do
          {:ok, signal} ->
            signal

          {:error, errors} when is_list(errors) ->
            raise Joi.ParseError, errors: errors

          {:error, reason} ->
            raise ArgumentError, "invalid signal: #{reason}"
        end
      end
    end
  end

  @doc false
  @spec __compile_definition__(keyword(), Macro.Env.t()) :: map() | no_return()
  def __compile_definition__(raw_opts, env) do
    case Joi.parse(@definition_schema, raw_opts) do
      {:ok, validated_opts} ->
        definition = Map.merge(@definition_defaults, Map.new(validated_opts))
        ensure_static_schema!(definition.schema, env)
        definition

      {:error, errors} ->
        raise CompileError,
          description:
            "Invalid configuration given to use Jido.Signal (#{env.module}): " <>
              Joi.prettify_errors(errors),
          file: env.file,
          line: env.line
    end
  end

  @doc false
  @spec __normalize_definition_attrs__(keyword() | map(), map()) ::
          {:ok, map()} | {:error, String.t()}
  def __normalize_definition_attrs__(opts, defaults) when is_list(opts) do
    if Keyword.keyword?(opts) do
      __normalize_definition_attrs__(Map.new(opts), defaults)
    else
      {:error, "expected Signal options to be a map or keyword list"}
    end
  end

  def __normalize_definition_attrs__(opts, defaults) when is_map(opts) do
    with {:ok, attrs} <- normalize_attribute_keys(opts) do
      {:ok, Map.merge(defaults, attrs)}
    end
  end

  def __normalize_definition_attrs__(_opts, _defaults),
    do: {:error, "expected Signal options to be a map or keyword list"}

  @doc false
  @spec validate_definition_schema(term(), keyword()) :: :ok | {:error, String.t()}
  def validate_definition_schema(value, _opts) do
    if Joi.Schema.schema?(value) do
      :ok
    else
      {:error, "must be a Joi schema"}
    end
  end

  @doc "Creates a Signal from an attribute map or keyword list."
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs),
      do: attrs |> Map.new() |> new(),
      else: {:error, "parse error: expected a map or keyword list"}
  end

  def new(attrs) when is_map(attrs) do
    with {:ok, attrs} <- normalize_attribute_keys(attrs) do
      attrs
      |> Map.put_new_lazy("id", &Jido.Id.uuid7/0)
      |> Map.put_new("specversion", "1.0")
      |> from_normalized_map(:constructor)
    end
  end

  def new(_attrs), do: {:error, "parse error: expected a map or keyword list"}

  @doc "Creates a Signal with an explicit type, data value, and attributes."
  @spec new(String.t(), term(), map() | keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(type, data, attrs \\ %{})

  def new(type, data, attrs) when is_binary(type) and is_list(attrs) do
    if Keyword.keyword?(attrs),
      do: new(type, data, Map.new(attrs)),
      else: {:error, "expected new/3 (type :: String.t(), data :: any(), attrs :: map/keyword)"}
  end

  def new(type, data, attrs) when is_binary(type) and is_map(attrs) do
    with {:ok, attrs} <- normalize_attribute_keys(attrs) do
      case Enum.find(["type", "data", "data_base64"], &Map.has_key?(attrs, &1)) do
        nil ->
          attrs |> Map.put("type", type) |> Map.put("data", data) |> new()

        key ->
          {:error, "attribute #{inspect(key)} must not be passed in attrs when calling new/3"}
      end
    end
  end

  def new(_type, _data, _attrs) do
    {:error, "expected new/3 (type :: String.t(), data :: any(), attrs :: map/keyword)"}
  end

  @doc "Creates a Signal and raises when its envelope is invalid."
  @spec new!(map() | keyword()) :: t() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, signal} -> signal
      {:error, reason} -> raise RuntimeError, reason
    end
  end

  @doc "Creates a Signal with explicit type and data, or raises when it is invalid."
  @spec new!(String.t(), term(), map() | keyword()) :: t() | no_return()
  def new!(type, data, attrs \\ %{}) do
    case new(type, data, attrs) do
      {:ok, signal} -> signal
      {:error, reason} -> raise ArgumentError, "invalid signal: #{reason}"
    end
  end

  @typedoc "One CloudEvents extension value."
  @type context_value :: boolean() | -2_147_483_648..2_147_483_647 | binary()

  @doc "Adds a CloudEvents extension context attribute."
  @spec put_context(t(), atom() | String.t(), context_value()) ::
          {:ok, t()} | {:error, String.t()}
  def put_context(%__MODULE__{} = signal, name, value) do
    with {:ok, name} <- normalize_extension_name(name),
         :ok <- validate_extension_value(value) do
      {:ok, %{signal | extensions: Map.put(signal.extensions, name, value)}}
    end
  end

  def put_context(_signal, _name, _value), do: {:error, "expected a Signal struct"}

  @doc "Gets a CloudEvents extension context attribute."
  @spec get_context(t(), atom() | String.t()) :: context_value() | nil
  def get_context(%__MODULE__{} = signal, name) when is_atom(name) or is_binary(name),
    do: Map.get(signal.extensions, to_string(name))

  def get_context(_signal, _name), do: nil

  @doc "Deletes a CloudEvents extension context attribute."
  @spec delete_context(t(), atom() | String.t()) :: t()
  def delete_context(%__MODULE__{} = signal, name) when is_atom(name) or is_binary(name),
    do: %{signal | extensions: Map.delete(signal.extensions, to_string(name))}

  def delete_context(signal, _name), do: signal

  @doc "Lists the CloudEvents extension context attribute names."
  @spec list_context(t()) :: [String.t()]
  def list_context(%__MODULE__{} = signal), do: Map.keys(signal.extensions)
  def list_context(_signal), do: []

  @doc false
  @spec __from_cloud_events__(map()) :: {:ok, t()} | {:error, String.t()}
  def __from_cloud_events__(map) when is_map(map) do
    with {:ok, attrs} <- normalize_attribute_keys(map), do: from_normalized_map(attrs, :wire)
  end

  def __from_cloud_events__(_map), do: {:error, "parse error: expected a map"}

  @doc false
  @spec normalize_extensions(map()) :: {:ok, %{optional(String.t()) => context_value()}} | {:error, String.t()}
  def normalize_extensions(attributes) when is_map(attributes) do
    Enum.reduce_while(Map.to_list(attributes), {:ok, %{}}, fn {name, value}, {:ok, acc} ->
      with {:ok, name} <- normalize_extension_name(name),
           :ok <- validate_extension_value(value) do
        if Map.has_key?(acc, name) do
          {:halt, {:error, "duplicate extension attribute #{inspect(name)}"}}
        else
          {:cont, {:ok, Map.put(acc, name, value)}}
        end
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def normalize_extensions(_attributes), do: {:error, "extensions must be a map"}

  @doc false
  @spec normalize_extension_name(term()) :: {:ok, String.t()} | {:error, String.t()}
  def normalize_extension_name(name) when is_atom(name),
    do: normalize_extension_name(Atom.to_string(name))

  def normalize_extension_name(name) when is_binary(name) do
    cond do
      name in @core_names ->
        {:error, "extension name #{inspect(name)} conflicts with a CloudEvents attribute"}

      Regex.match?(@extension_name_pattern, name) ->
        {:ok, name}

      true ->
        {:error,
         "extension name #{inspect(name)} must start with a lower-case letter, contain only lower-case letters and digits, and have at most 20 characters"}
    end
  end

  def normalize_extension_name(name), do: {:error, "invalid extension name #{inspect(name)}"}

  @doc false
  def validate_uri_reference(value, _opts) when is_binary(value) do
    if valid_uri_text?(value) do
      case URI.new(value) do
        {:ok, _uri} -> :ok
        {:error, reason} -> {:error, "must be a URI-reference: #{inspect(reason)}"}
      end
    else
      {:error, "must be a valid URI-reference"}
    end
  end

  def validate_uri_reference(_value, _opts), do: {:error, "must be a URI-reference"}

  @doc false
  def validate_absolute_uri(value, _opts) when is_binary(value) do
    if valid_uri_text?(value) do
      case URI.new(value) do
        {:ok, %URI{scheme: scheme}} when is_binary(scheme) and scheme != "" -> :ok
        _result -> {:error, "must be an absolute URI"}
      end
    else
      {:error, "must be an absolute URI"}
    end
  end

  def validate_absolute_uri(_value, _opts), do: {:error, "must be an absolute URI"}

  @doc false
  def validate_rfc3339(value, _opts) when is_binary(value) do
    with true <- String.valid?(value),
         [prefix, second, fraction, offset] <-
           Regex.run(@rfc3339_pattern, value, capture: :all_but_first),
         parse_second <- if(second == "60", do: "59", else: second),
         {:ok, datetime, _offset} <-
           DateTime.from_iso8601(String.upcase(prefix <> parse_second <> fraction <> offset)),
         true <- second != "60" or leap_second_position?(datetime) do
      :ok
    else
      {:error, reason} -> {:error, "must be an RFC 3339 timestamp: #{inspect(reason)}"}
      _invalid -> {:error, "must be an RFC 3339 timestamp"}
    end
  end

  def validate_rfc3339(_value, _opts), do: {:error, "must be an RFC 3339 timestamp"}

  @doc false
  def validate_utf8_string(value, _opts) when is_binary(value) do
    cond do
      not String.valid?(value) ->
        {:error, "must be valid UTF-8"}

      not valid_context_characters?(value) ->
        {:error, "must not contain controls or noncharacters"}

      true ->
        :ok
    end
  end

  def validate_utf8_string(_value, _opts), do: {:error, "must be valid UTF-8"}

  defp from_normalized_map(attrs, boundary) do
    with :ok <- validate_specversion(attrs),
         :ok <- validate_legacy_wire_version(attrs),
         {:ok, data, data_present?, data_base64?} <- extract_data(attrs),
         {:ok, extensions} <- extract_extensions(attrs, boundary) do
      parse_signal(attrs, data, data_present?, data_base64?, extensions)
    end
  end

  defp extract_extensions(attrs, :constructor) do
    explicit = Map.get(attrs, "extensions", %{})
    unknown = Map.drop(attrs, @constructor_names ++ [@legacy_wire_version_key])

    with {:ok, explicit} <- normalize_extensions(explicit),
         {:ok, unknown} <- normalize_extensions(unknown),
         :ok <- reject_duplicate_extensions(explicit, unknown) do
      {:ok, Map.merge(unknown, explicit)}
    else
      {:error, reason} -> {:error, "parse error: #{reason}"}
    end
  end

  defp extract_extensions(attrs, :wire) do
    attrs
    |> Map.drop(@core_names ++ [@legacy_wire_version_key])
    |> Map.reject(fn {_name, value} -> is_nil(value) end)
    |> normalize_extensions()
    |> case do
      {:ok, extensions} -> {:ok, extensions}
      {:error, reason} -> {:error, "parse error: #{reason}"}
    end
  end

  defp reject_duplicate_extensions(explicit, unknown) do
    case Enum.find(Map.keys(explicit), &Map.has_key?(unknown, &1)) do
      nil -> :ok
      name -> {:error, "duplicate extension attribute #{inspect(name)}"}
    end
  end

  defp parse_signal(attrs, data, data_present?, data_base64?, extensions) do
    signal =
      struct(__MODULE__,
        data: data,
        data_present?: data_present?,
        data_base64?: data_base64?,
        datacontenttype: Map.get(attrs, "datacontenttype"),
        dataschema: Map.get(attrs, "dataschema"),
        extensions: extensions,
        id: Map.get(attrs, "id"),
        source: Map.get(attrs, "source"),
        specversion: normalize_specversion(Map.get(attrs, "specversion")),
        subject: Map.get(attrs, "subject"),
        time: normalize_time(Map.get(attrs, "time")),
        type: Map.get(attrs, "type")
      )

    case Joi.parse(schema(), signal) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, "parse error: #{Joi.prettify_errors(errors)}"}
    end
  end

  defp extract_data(attrs) do
    case {Map.fetch(attrs, "data"), Map.fetch(attrs, "data_base64")} do
      {{:ok, _data}, {:ok, _encoded}} ->
        {:error, "parse error: data and data_base64 are mutually exclusive"}

      {{:ok, data}, :error} ->
        {:ok, data, true, is_binary(data) and not String.valid?(data)}

      {:error, {:ok, encoded}} ->
        decode_data_base64(encoded)

      {:error, :error} ->
        {:ok, nil, false, false}
    end
  end

  defp decode_data_base64(encoded) when is_binary(encoded) do
    case Base.decode64(encoded) do
      {:ok, binary} -> {:ok, binary, true, true}
      :error -> {:error, "parse error: data_base64 must be valid Base64"}
    end
  end

  defp decode_data_base64(_encoded),
    do: {:error, "parse error: data_base64 must be a Base64 string"}

  defp normalize_attribute_keys(map) when is_map(map) do
    Enum.reduce_while(Map.to_list(map), {:ok, %{}}, fn {key, value}, {:ok, normalized} ->
      with {:ok, key} <- normalize_attribute_key(key),
           false <- Map.has_key?(normalized, key) do
        {:cont, {:ok, Map.put(normalized, key, value)}}
      else
        true -> {:halt, {:error, "parse error: duplicate attribute #{inspect(key)}"}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_attribute_key(key) when is_atom(key), do: {:ok, Atom.to_string(key)}

  defp normalize_attribute_key(key) when is_binary(key) do
    if String.valid?(key),
      do: {:ok, key},
      else: {:error, "parse error: attribute names must be valid UTF-8 strings"}
  end

  defp normalize_attribute_key(key),
    do: {:error, "parse error: attribute keys must be atoms or strings, got: #{inspect(key)}"}

  defp normalize_specversion("1.0.2"), do: "1.0"
  defp normalize_specversion(value), do: value

  defp normalize_time(%DateTime{} = time), do: DateTime.to_iso8601(time)
  defp normalize_time(time), do: time

  defp validate_specversion(%{"specversion" => value}) when not is_nil(value), do: :ok
  defp validate_specversion(_attrs), do: {:error, "parse error: specversion is required"}

  defp validate_legacy_wire_version(%{@legacy_wire_version_key => version})
       when version in @legacy_wire_versions,
       do: :ok

  defp validate_legacy_wire_version(%{@legacy_wire_version_key => nil}), do: :ok

  defp validate_legacy_wire_version(map)
       when not is_map_key(map, @legacy_wire_version_key),
       do: :ok

  defp validate_legacy_wire_version(%{@legacy_wire_version_key => version}) do
    {:error, "parse error: unsupported jido_schema_version #{inspect(version)}"}
  end

  defp validate_extension_value(value) when is_boolean(value), do: :ok

  defp validate_extension_value(value)
       when is_integer(value) and value >= @extension_min_integer and
              value <= @extension_max_integer,
       do: :ok

  defp validate_extension_value(value) when is_binary(value), do: :ok

  defp validate_extension_value(value) do
    {:error,
     "extension values must be a Boolean, signed 32-bit Integer, String, Binary, URI, URI-reference, or Timestamp; got: #{inspect(value)}"}
  end

  defp valid_context_characters?(<<>>), do: true

  defp valid_context_characters?(<<codepoint::utf8, _rest::binary>>)
       when codepoint in 0..31 or codepoint in 127..159 or codepoint in 0xFDD0..0xFDEF or
              rem(codepoint, 0x10000) in [0xFFFE, 0xFFFF],
       do: false

  defp valid_context_characters?(<<_codepoint::utf8, rest::binary>>),
    do: valid_context_characters?(rest)

  # Validate UTC placement. The producer owns the announced leap-second date.
  defp leap_second_position?(datetime) do
    date = DateTime.to_date(datetime)
    datetime.hour == 23 and datetime.minute == 59 and date.day == Date.days_in_month(date)
  end

  @doc false
  def validate_media_type(value, _opts) when is_binary(value) do
    if String.valid?(value) and Regex.match?(@media_type_pattern, value) do
      :ok
    else
      {:error, "must be a valid media type"}
    end
  end

  def validate_media_type(_value, _opts), do: {:error, "must be a valid media type"}

  defp valid_uri_text?(value) do
    String.valid?(value) and Regex.match?(@uri_reference_pattern, value)
  end

  defp ensure_static_schema!(schema, env) do
    case Jido.Joi.validate_static(schema) do
      :ok ->
        :ok

      {:error, reason} ->
        raise CompileError,
          description:
            ":schema must be static module data; #{reason}. " <>
              "Use named MFA effects such as {Module, :function, args}",
          file: env.file,
          line: env.line
    end

    try do
      Macro.escape(schema)
      :ok
    rescue
      ArgumentError ->
        raise CompileError,
          description:
            ":schema must be static module data that can be stored in the Signal module. " <>
              "Use named MFA effects such as {Module, :function, args}",
          file: env.file,
          line: env.line
    end
  end
end
