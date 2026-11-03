defmodule Jido.Codec do
  @moduledoc """
  Encodes runtime values and decodes trusted versioned documents.

  ## Supported features

  `Jido.Codec` owns the public encode and decode workflow:

  * route documents by their required string `type` and positive integer `vsn`;
  * select the current writer through `Jido.Codec.Encoder`, with a trusted
    private codec-index fallback for external codecs;
  * contain codec callback failures and return stable ordered issues;
  * enforce complete-document, JSON byte, duplicate-key, and nesting limits;
  * read the atomically published codec index only when document routing needs
    it and the caller does not pass `:registry`.

  Domain codecs implement `Jido.Codec.Contract` and own their document fields
  and semantic validation. Catalog Discovery owns module scanning and atomic
  publication. Codec does not own persistence, execution, or automatic
  document upgrades.

  The `Jido.Codec` namespace also owns the internal compile-time support that
  makes definitions discoverable: static-data validation and the common Action
  and Flow declaration contract. These helpers do not
  add more runtime operations to this facade.

  An explicit `:registry` option bypasses Discovery.
  """

  alias Jido.Codec.{Contract, Document, Error, Issue, Registry, Static}

  @default_maximum_json_bytes 8_388_608
  @catalog_snapshot_key {:jido, :catalog_snapshot}
  @option_keys [:registry, :codec, :maximum_json_bytes]

  @typedoc "A JSON object produced or consumed by a document codec."
  @type document :: Contract.document()

  @doc "Encodes one supported runtime value."
  @spec encode(term(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def encode(value, opts \\ []) do
    opts = options!(opts)
    registry = registry!(opts)
    maximum_bytes = maximum_json_bytes!(opts)

    with {:ok, codec} <- encoder(value, registry, opts),
         {:ok, document} <- safe_encode(codec, value, registry),
         :ok <- encoded_document(document, codec, maximum_bytes) do
      {:ok, document}
    end
  end

  @doc "Encodes one supported runtime value as JSON."
  @spec encode_json(term(), keyword()) :: {:ok, String.t()} | {:error, Error.t()}
  def encode_json(value, opts \\ []) do
    with {:ok, document} <- encode(value, opts), do: {:ok, JSON.encode!(document)}
  end

  @doc "Decodes one trusted runtime JSON document."
  @spec decode_json(String.t(), keyword()) :: {:ok, struct()} | {:error, [Issue.t()]}
  def decode_json(json, opts \\ []) do
    opts = options!(opts)
    maximum_bytes = maximum_json_bytes!(opts)

    case Document.decode_json(json, maximum_bytes) do
      {:ok, document} -> route(document, opts)
      {:error, %Document.Error{} = error} -> document_error(error)
    end
  end

  @doc "Decodes one trusted runtime document."
  @spec decode(term(), keyword()) :: {:ok, struct()} | {:error, [Issue.t()]}
  def decode(document, opts \\ []) do
    opts = options!(opts)
    maximum_bytes = maximum_json_bytes!(opts)

    decode_checked(document, opts, &Document.check_json(&1, maximum_bytes))
  end

  @doc "Checks that codec data contains no runtime-only values."
  @spec validate_static(term()) :: :ok | {:error, Error.InvalidError.t()}
  def validate_static(value) do
    case Static.validate(value) do
      :ok -> :ok
      {:error, message} -> {:error, Error.invalid(:non_static_data, message)}
    end
  end

  defp decode_checked(document, opts, check) do
    with :ok <- check.(document),
         {:ok, value} <- route(document, opts) do
      {:ok, value}
    else
      {:error, %Document.Error{} = error} ->
        document_error(error)

      {:error, issues} when is_list(issues) ->
        {:error, issues}
    end
  end

  defp route(%{"type" => type, "vsn" => vsn} = document, opts)
       when is_binary(type) and byte_size(type) in 1..255 and is_integer(vsn) and vsn > 0 do
    run_codec(document, type, vsn, registry!(opts), opts[:codec])
  end

  defp route(%{"type" => type, "vsn" => _vsn}, _opts) when is_binary(type),
    do:
      issue(
        :invalid_document_vsn,
        ["vsn"],
        "codec document vsn must be a positive integer"
      )

  defp route(%{"type" => type}, opts) when is_binary(type) do
    issue(:missing_document_vsn, ["vsn"], "codec document vsn is required", %{
      supported_vsns: Registry.codec_vsns(registry!(opts), type)
    })
  end

  defp route(%{"type" => type}, _opts) when not is_binary(type),
    do: issue(:invalid_document_type, ["type"], "codec document type must be a string")

  defp route(%{} = document, _opts) when not is_struct(document),
    do: issue(:missing_document_type, ["type"], "codec document type is required")

  defp route(_document, _opts),
    do: issue(:invalid_document, [], "codec document must be a JSON object")

  defp run_codec(document, type, vsn, registry, nil) do
    case Registry.codec(registry, type, vsn) do
      {:ok, codec} ->
        safe_decode(codec, document, registry)

      {:error, :unknown_codec} ->
        supported = Registry.codec_vsns(registry, type)
        path = if supported == [], do: ["type"], else: ["vsn"]

        issue(:unsupported_document, path, "codec document type or vsn is not supported", %{
          type: type,
          vsn: vsn,
          supported_vsns: supported
        })
    end
  end

  defp run_codec(document, type, vsn, registry, codec) when is_atom(codec) do
    case codec_metadata(codec, :decode) do
      {:ok, %{type: ^type, vsn: ^vsn}} -> safe_decode(codec, document, registry)
      {:ok, _metadata} -> unsupported_document(type, vsn, [])
      {:error, error} -> {:error, [error]}
    end
  end

  defp safe_decode(codec, document, registry) do
    case codec.decode(document, registry) do
      {:ok, %_{} = value} ->
        {:ok, value}

      {:error, issues} when is_list(issues) and issues != [] ->
        if Enum.all?(issues, &Issue.valid?/1),
          do: {:error, issues},
          else: invalid_codec_return(codec)

      _other ->
        invalid_codec_return(codec)
    end
  rescue
    error -> codec_failure(codec, :error, Exception.message(error))
  catch
    kind, reason -> codec_failure(codec, kind, inspect(reason, limit: 20, printable_limit: 1_000))
  end

  defp safe_encode(codec, value, registry) do
    case codec.encode(value, registry) do
      {:ok, %{} = document} when not is_struct(document) ->
        {:ok, document}

      {:error, %{__exception__: true} = error} ->
        {:error, public_encode_error(error)}

      _other ->
        {:error,
         Error.internal(
           :invalid_codec_return,
           "document codec returned an invalid value",
           %{codec: codec}
         )}
    end
  rescue
    error ->
      {:error,
       Error.internal(
         :codec_failure,
         "document codec failed",
         %{codec: codec, failure_kind: :error, reason: Exception.message(error)}
       )}
  catch
    kind, reason ->
      {:error,
       Error.internal(
         :codec_failure,
         "document codec failed",
         %{codec: codec, failure_kind: kind, reason: inspect(reason)}
       )}
  end

  defp public_encode_error(%Error.InvalidError{} = error), do: error
  defp public_encode_error(%Error.InternalError{} = error), do: error

  defp public_encode_error(error) do
    details =
      error
      |> Map.get(:details, %{})
      |> normalize_error_details(error)

    code = Map.get(error, :code) || Map.get(error, :reason) || :invalid_value
    message = Exception.message(error)

    if Map.get(error, :class) == :internal,
      do: Error.internal(code, message, details),
      else: Error.invalid(code, message, details)
  end

  defp normalize_error_details(details, error) when is_map(details) do
    case Map.get(error, :path) do
      path when is_list(path) and path != [] -> Map.put_new(details, :path, path)
      _path -> details
    end
  end

  defp normalize_error_details(_details, _error), do: %{}

  defp invalid_codec_return(codec),
    do:
      issue(:invalid_codec_return, [], "document codec returned an invalid value", %{
        codec: codec
      })

  defp codec_failure(codec, kind, reason),
    do:
      issue(:codec_failure, [], "document codec failed", %{
        codec: codec,
        failure_kind: kind,
        reason: reason
      })

  defp encoded_document(%{"type" => type, "vsn" => vsn} = document, codec, maximum_bytes) do
    with :ok <- Document.check_json(document, maximum_bytes),
         {:ok, %{type: ^type, vsn: ^vsn}} <- codec_metadata(codec, :encode) do
      :ok
    else
      {:error, %Document.Error{reason: :bytes, details: details}} ->
        {:error,
         Error.invalid(
           :document_too_large,
           "encoded codec document exceeds its JSON byte limit",
           details
         )}

      {:error, %Document.Error{} = error} ->
        {:error, Error.invalid(:invalid_document, error.message, error.details)}

      {:ok, _metadata} ->
        {:error,
         Error.invalid(
           :unsupported_document,
           "document codec returned the wrong type or vsn"
         )}

      {:error, %Issue{} = issue} ->
        {:error, Error.invalid(issue.code, issue.message, issue.details)}
    end
  end

  defp encoded_document(_document, _codec, _maximum_bytes),
    do: {:error, Error.invalid(:invalid_document, "codec returned an invalid document")}

  defp encoder(value, registry, opts) do
    case opts[:codec] do
      nil ->
        case Jido.Codec.Encoder.codec(value) do
          {:ok, codec} ->
            {:ok, codec}

          :error ->
            case Registry.encoder(registry, value) do
              {:ok, codec} -> {:ok, codec}
              {:error, :unknown_encoder} -> unsupported_value()
            end
        end

      codec when is_atom(codec) ->
        case codec_metadata(codec, :encode) do
          {:ok, _metadata} ->
            {:ok, codec}

          {:error, %Issue{} = issue} ->
            {:error, Error.internal(issue.code, issue.message, issue.details)}
        end

      _other ->
        unsupported_value()
    end
  end

  defp codec_metadata(codec, operation) do
    case Contract.metadata(codec, operation) do
      {:ok, metadata} ->
        {:ok, metadata}

      {:error, {:metadata_failure, kind, reason}} ->
        reason =
          if is_exception(reason),
            do: Exception.message(reason),
            else: inspect(reason, limit: 20, printable_limit: 1_000)

        {:error,
         Issue.new(:codec_failure, [], "codec metadata failed",
           details: %{codec: codec, failure_kind: kind, reason: reason}
         )}

      {:error, {:invalid_metadata, _metadata}} ->
        {:error, Issue.new(:invalid_codec, [], "codec metadata is invalid")}

      {:error, :invalid_contract} ->
        {:error, Issue.new(:invalid_codec, [], "codec contract is invalid")}
    end
  end

  defp unsupported_value do
    {:error, Error.invalid(:unsupported_value, "no codec supports this value")}
  end

  defp unsupported_document(type, vsn, supported) do
    issue(:unsupported_document, ["type"], "codec document type or vsn is not supported", %{
      type: type,
      vsn: vsn,
      supported_vsns: supported
    })
  end

  defp options!(opts) when is_list(opts), do: Keyword.validate!(opts, @option_keys)

  defp options!(opts),
    do: raise(ArgumentError, "codec options must be a keyword list, got: #{inspect(opts)}")

  defp maximum_json_bytes!(opts) do
    value = Keyword.get_lazy(opts, :maximum_json_bytes, &configured_maximum_json_bytes/0)

    if is_integer(value) and value > 0,
      do: value,
      else: raise(ArgumentError, "maximum_json_bytes must be a positive integer")
  end

  defp configured_maximum_json_bytes do
    :jido
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:maximum_json_bytes, @default_maximum_json_bytes)
  end

  defp registry!(opts) do
    case Keyword.get(opts, :registry) do
      nil -> published_codec_index!()
      %Registry{} = registry -> registry
      entries when is_map(entries) and not is_struct(entries) -> Registry.new!(entries)
      value -> raise ArgumentError, "Codec Registry is invalid: #{inspect(value)}"
    end
  end

  defp published_codec_index! do
    case :persistent_term.get(@catalog_snapshot_key, :not_initialized) do
      %{registry: %Registry{} = registry} ->
        registry

      {:error, reason} ->
        raise Error.internal(
                :catalog_initialization_failed,
                "Catalog initialization failed: #{inspect(reason)}",
                %{reason: reason}
              )

      :not_initialized ->
        raise Error.internal(:catalog_not_initialized, "Catalog is not initialized")
    end
  end

  defp document_error(%Document.Error{} = error),
    do: {:error, [Issue.new(error.reason, error.path, error.message, details: error.details)]}

  defp issue(code, path, message, details \\ %{}),
    do: {:error, [Issue.new(code, path, message, details: details)]}
end
