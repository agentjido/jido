defmodule Jido.Authoring do
  @moduledoc """
  Decodes runtime JSON definitions and encodes canonical authoring values.

  This module owns JSON parsing, complete-document limits, codec selection,
  callback containment, and ordered issues.
  """

  alias Jido.Authoring.{Codec, Document, Error, Issue, Registry, Static}

  require Jido.Authoring.Limits

  @default_maximum_json_bytes 8_388_608
  @maximum_depth Jido.Authoring.Limits.maximum_depth()
  @maximum_collection_size Jido.Authoring.Limits.maximum_collection_size()
  @maximum_document_nodes Jido.Authoring.Limits.maximum_document_nodes()
  @option_keys [:registry, :codec, :maximum_json_bytes]

  @doc "Encodes one canonical authoring value."
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

  @doc "Encodes one canonical authoring value as JSON."
  @spec encode_json(term(), keyword()) :: {:ok, String.t()} | {:error, Error.t()}
  def encode_json(value, opts \\ []) do
    with {:ok, document} <- encode(value, opts), do: Jason.encode(document)
  end

  @doc "Decodes one runtime authoring JSON document."
  @spec decode_json(String.t(), keyword()) :: {:ok, struct()} | {:error, [Issue.t()]}
  def decode_json(json, opts \\ []) do
    opts = options!(opts)
    registry = registry!(opts)
    maximum_bytes = maximum_json_bytes!(opts)

    case parse_json(json, maximum_bytes) do
      {:ok, document} -> decode_document(document, registry, opts[:codec], &Document.check/1)
      {:error, issues} -> {:error, issues}
    end
  end

  @doc "Decodes one runtime authoring document."
  @spec decode(term(), keyword()) :: {:ok, struct()} | {:error, [Issue.t()]}
  def decode(document, opts \\ []) do
    opts = options!(opts)
    maximum_bytes = maximum_json_bytes!(opts)

    decode_document(
      document,
      registry!(opts),
      opts[:codec],
      &Document.check_json(&1, maximum_bytes)
    )
  end

  @doc "Checks that authoring data contains no runtime-only values."
  @spec validate_static(term()) :: :ok | {:error, Error.InvalidError.t()}
  def validate_static(value) do
    case Static.validate(value) do
      :ok -> :ok
      {:error, message} -> {:error, Error.invalid(:non_static_data, message)}
    end
  end

  defp decode_document(document, registry, codec, check) do
    with :ok <- check.(document),
         {:ok, value} <- route(document, registry, codec) do
      {:ok, value}
    else
      {:error, %Document.Error{} = error} ->
        {:error, [Issue.new(error.reason, [], error.message, details: error.details)]}

      {:error, issues} when is_list(issues) ->
        {:error, issues}
    end
  end

  defp route(%{"type" => type, "vsn" => vsn} = document, registry, codec)
       when is_binary(type) and byte_size(type) in 1..255 and is_integer(vsn) and vsn > 0 do
    run_codec(document, type, vsn, registry, codec)
  end

  defp route(%{"type" => type, "vsn" => _vsn}, _registry, _codec) when is_binary(type),
    do:
      issue(
        :invalid_document_vsn,
        ["vsn"],
        "authoring document vsn must be a positive integer"
      )

  defp route(%{"type" => type}, registry, _codec) when is_binary(type) do
    issue(:missing_document_vsn, ["vsn"], "authoring document vsn is required", %{
      supported_vsns: Registry.codec_vsns(registry, type)
    })
  end

  defp route(%{"type" => type}, _registry, _codec) when not is_binary(type),
    do: issue(:invalid_document_type, ["type"], "authoring document type must be a string")

  defp route(%{} = document, _registry, _codec) when not is_struct(document),
    do: issue(:missing_document_type, ["type"], "authoring document type is required")

  defp route(_document, _registry, _codec),
    do: issue(:invalid_document, [], "authoring document must be a JSON object")

  defp run_codec(document, type, vsn, registry, nil) do
    case Registry.codec(registry, type, vsn) do
      {:ok, codec} ->
        safe_decode(codec, document, registry)

      {:error, :unknown_codec} ->
        supported = Registry.codec_vsns(registry, type)
        path = if supported == [], do: ["type"], else: ["vsn"]

        issue(:unsupported_document, path, "authoring document type or vsn is not supported", %{
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
    case codec.decode_document(document, registry) do
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
    case codec.encode_document(value, registry) do
      {:ok, %{} = document} when not is_struct(document) ->
        {:ok, document}

      {:error, %{__exception__: true} = error} ->
        {:error, public_encode_error(error)}

      _other ->
        {:error,
         Error.internal(
           :invalid_codec_return,
           "authoring document codec returned an invalid value",
           %{codec: codec}
         )}
    end
  rescue
    error ->
      {:error,
       Error.internal(
         :codec_failure,
         "authoring document codec failed",
         %{codec: codec, failure_kind: :error, reason: Exception.message(error)}
       )}
  catch
    kind, reason ->
      {:error,
       Error.internal(
         :codec_failure,
         "authoring document codec failed",
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
      issue(:invalid_codec_return, [], "authoring document codec returned an invalid value", %{
        codec: codec
      })

  defp codec_failure(codec, kind, reason),
    do:
      issue(:codec_failure, [], "authoring document codec failed", %{
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
           "encoded authoring document exceeds its JSON byte limit",
           details
         )}

      {:error, %Document.Error{} = error} ->
        {:error, Error.invalid(:invalid_document, error.message, error.details)}

      {:ok, _metadata} ->
        {:error,
         Error.invalid(
           :unsupported_document,
           "authoring document codec returned the wrong type or vsn"
         )}

      {:error, %Issue{} = issue} ->
        {:error, Error.invalid(issue.code, issue.message, issue.details)}
    end
  end

  defp encoded_document(_document, _codec, _maximum_bytes),
    do: {:error, Error.invalid(:invalid_document, "authoring codec returned an invalid document")}

  defp encoder(value, registry, opts) do
    case opts[:codec] do
      nil ->
        case Registry.encoder(registry, value) do
          {:ok, codec} -> {:ok, codec}
          {:error, :unknown_encoder} -> unsupported_value()
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
    case Codec.metadata(codec, operation) do
      {:ok, metadata} ->
        {:ok, metadata}

      {:error, {:metadata_failure, kind, reason}} ->
        reason =
          if is_exception(reason),
            do: Exception.message(reason),
            else: inspect(reason, limit: 20, printable_limit: 1_000)

        {:error,
         Issue.new(:codec_failure, [], "authoring codec metadata failed",
           details: %{codec: codec, failure_kind: kind, reason: reason}
         )}

      {:error, {:invalid_metadata, _metadata}} ->
        {:error, Issue.new(:invalid_codec, [], "authoring codec metadata is invalid")}

      {:error, :invalid_contract} ->
        {:error, Issue.new(:invalid_codec, [], "authoring codec contract is invalid")}
    end
  end

  defp unsupported_value do
    {:error, Error.invalid(:unsupported_value, "authoring has no codec for this value")}
  end

  defp unsupported_document(type, vsn, supported) do
    issue(:unsupported_document, ["type"], "authoring document type or vsn is not supported", %{
      type: type,
      vsn: vsn,
      supported_vsns: supported
    })
  end

  defp parse_json(json, maximum_bytes)
       when is_binary(json) and byte_size(json) <= maximum_bytes do
    case Jason.decode(json, strings: :copy, objects: :ordered_objects) do
      {:ok, document} ->
        case plain_json(document, [], 0, @maximum_document_nodes) do
          {:ok, document, _remaining} -> {:ok, document}
          {:error, _issues} = error -> error
        end

      {:error, error} ->
        issue(:invalid_json, [], Exception.message(error))
    end
  end

  defp parse_json(_json, maximum_bytes),
    do:
      issue(:invalid_json, [], "expected a JSON string of at most #{maximum_bytes} bytes", %{
        maximum_bytes: maximum_bytes
      })

  defp plain_json(_value, _path, _depth, remaining) when remaining <= 0,
    do:
      issue(:nodes, [], "authoring document exceeds its total node limit", %{
        maximum_nodes: @maximum_document_nodes
      })

  defp plain_json(_value, _path, depth, _remaining) when depth > @maximum_depth,
    do:
      issue(:depth, [], "authoring document exceeds its nesting limit", %{
        maximum_depth: @maximum_depth
      })

  defp plain_json(%Jason.OrderedObject{values: pairs}, path, depth, remaining) do
    cond do
      length(pairs) > @maximum_collection_size ->
        collection_issue()

      key = duplicate_key(pairs) ->
        issue(:duplicate_key, path ++ [key], "JSON object contains a duplicate key", %{key: key})

      true ->
        Enum.reduce_while(pairs, {:ok, %{}, remaining - 1}, fn {key, value}, {:ok, result, left} ->
          with {:ok, _key, left} <- plain_json(key, path, depth + 1, left),
               {:ok, value, left} <- plain_json(value, path ++ [key], depth + 1, left) do
            {:cont, {:ok, Map.put(result, key, value), left}}
          else
            {:error, _issues} = error -> {:halt, error}
          end
        end)
    end
  end

  defp plain_json(values, path, depth, remaining) when is_list(values) do
    if length(values) > @maximum_collection_size do
      collection_issue()
    else
      values
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, [], remaining - 1}, fn {value, index}, {:ok, result, left} ->
        case plain_json(value, path ++ [index], depth + 1, left) do
          {:ok, value, left} -> {:cont, {:ok, [value | result], left}}
          {:error, _issues} = error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, result, left} -> {:ok, Enum.reverse(result), left}
        {:error, _issues} = error -> error
      end
    end
  end

  defp plain_json(value, _path, _depth, remaining), do: {:ok, value, remaining - 1}

  defp collection_issue do
    issue(:collection, [], "authoring document collection exceeds its size limit", %{
      maximum_size: @maximum_collection_size
    })
  end

  defp duplicate_key(pairs) do
    Enum.reduce_while(pairs, MapSet.new(), fn {key, _value}, seen ->
      if MapSet.member?(seen, key),
        do: {:halt, key},
        else: {:cont, MapSet.put(seen, key)}
    end)
    |> case do
      %MapSet{} -> nil
      key -> key
    end
  end

  defp options!(opts) when is_list(opts), do: Keyword.validate!(opts, @option_keys)

  defp options!(opts),
    do: raise(ArgumentError, "authoring options must be a keyword list, got: #{inspect(opts)}")

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
      nil -> Jido.Discovery.registry()
      %Registry{} = registry -> registry
      entries when is_map(entries) and not is_struct(entries) -> Registry.new!(entries)
      value -> raise ArgumentError, "authoring registry is invalid: #{inspect(value)}"
    end
  end

  defp issue(code, path, message, details \\ %{}),
    do: {:error, [Issue.new(code, path, message, details: details)]}
end
