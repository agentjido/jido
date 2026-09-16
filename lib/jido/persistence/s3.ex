defmodule Jido.Persistence.S3 do
  @moduledoc """
  Stores Jido records as single S3 objects with conditional writes.

  This adapter is for low-frequency records. It does not provide an AWS
  client. The host supplies `:request_fn`, which signs and sends one request.
  The function receives a map with `:method` (`:get`, `:put`, or `:delete`),
  `:bucket`, `:key`, `:headers`, `:body`, `:timeout_ms`, `:retry` (`false`), and
  `:follow_redirects` (`false`). It returns `{:ok, %{status: integer,
  headers: map_or_list, body: binary, code: string_or_nil}}` or
  `{:error, {:rejected, reason} | {:indeterminate, reason} | reason}`. The
  `:code` field is the parsed S3 error code; it is needed to tell a missing
  object from a missing bucket. Header names are case insensitive.

  The host owns the endpoint, credentials, signing, HTTP client, and any
  connection pool. It must honor `:timeout_ms`, disable retries for writes and
  redirects, and report a lost write reply as indeterminate. The adapter also
  bounds each request in its own process. A timeout after a write starts is
  indeterminate. Do not switch endpoints or replicas after such a result. Keep
  credentials, object bodies, raw ETags, and signed headers out of host logs
  and telemetry.

  `:bucket` and `:request_fn` are required. `:prefix` defaults to `"jido/"`.
  `:timeout_ms` defaults to 5 seconds. A binary key maps to the prefix plus
  `"k_"` and unpadded Base64 URL encoding. The mapping is collision free,
  including for an empty key. An object can have at most 5,000,000 bytes.
  The adapter stores Jido's record bytes without changing their format.

  Each write sends a SHA-256 checksum. Each read asks S3 for the checksum and
  validates it before returning bytes or an ETag-based token. The endpoint must return
  `x-amz-checksum-sha256` for these objects. Tokens bind an ETag to the bucket
  and object key. ETags are opaque conditions; they
  are not content hashes, leases, or unique activation generations. A direct
  byte compare-and-swap uses one GET and one conditional PUT. The Store's token
  path uses its original GET and one conditional PUT. A create uses one PUT.

  Use a bucket with supported read consistency and conditional PUT behavior.
  Record owners define expiry and tombstone rules. `delete/2` is only for
  explicit maintenance. In a versioned bucket it can create a delete marker;
  older versions may remain. Do not use maintenance deletion while a writer
  can use the key.
  """

  @behaviour Jido.Persistence.Adapter

  @max_object_bytes 5_000_000
  @default_timeout_ms 5_000
  @max_timeout_ms 120_000
  @allowed_options [:bucket, :prefix, :request_fn, :timeout_ms]

  @impl true
  def validate_options(opts) do
    cond do
      not Keyword.keyword?(opts) ->
        {:error, :invalid_options}

      Enum.any?(Keyword.keys(opts), &(&1 not in @allowed_options)) ->
        {:error, :unknown_option}

      length(Keyword.keys(opts)) != length(Enum.uniq(Keyword.keys(opts))) ->
        {:error, :duplicate_option}

      not (is_binary(opts[:bucket]) and byte_size(opts[:bucket]) > 0) ->
        {:error, :invalid_bucket}

      not is_function(opts[:request_fn], 1) ->
        {:error, :invalid_request_fn}

      not valid_prefix?(Keyword.get(opts, :prefix, "jido/")) ->
        {:error, :invalid_prefix}

      not valid_timeout?(Keyword.get(opts, :timeout_ms, @default_timeout_ms)) ->
        {:error, :invalid_timeout}

      true ->
        :ok
    end
  end

  @impl true
  def get(key, opts) when is_binary(key) and is_list(opts) do
    with :ok <- validate_options(opts),
         :ok <- validate_key(key, opts),
         {:ok, response} <- request(:get, key, %{"x-amz-checksum-mode" => "ENABLED"}, nil, opts) do
      case response do
        %{status: 200} ->
          read_object(response, key, opts)

        %{status: 404, code: "NoSuchKey"} ->
          {:error, :not_found}

        %{status: 404, code: "NoSuchBucket"} ->
          {:error, :missing_bucket}

        %{status: 404, headers: headers} = response ->
          if header(headers, "x-amz-delete-marker") == "true",
            do: {:error, :not_found},
            else: {:error, {:s3_status, response.status}}

        %{status: 403} ->
          {:error, :access_denied}

        %{status: status} when is_integer(status) ->
          {:error, {:s3_status, status}}

        _ ->
          {:error, :invalid_s3_response}
      end
    end
  end

  @impl true
  def compare_and_swap(key, expected, value, opts)
      when is_binary(key) and is_binary(value) and is_list(opts) do
    with :ok <- preflight(key, value, opts),
         {:ok, condition} <- condition(key, expected, opts) do
      conditional_put(key, condition, value, opts)
    else
      {:error, :conflict} = error -> error
      {:error, {:rejected, _reason}} = error -> error
      {:error, reason} -> {:error, {:rejected, reason}}
    end
  end

  @impl true
  def put(key, value, opts) when is_binary(key) and is_binary(value) and is_list(opts) do
    with :ok <- preflight(key, value, opts) do
      write(key, %{}, value, opts)
    end
  end

  @impl true
  def delete(key, opts) when is_binary(key) and is_list(opts) do
    with :ok <- validate_options(opts),
         :ok <- validate_key(key, opts),
         {:ok, response} <- request(:delete, key, %{}, nil, opts) do
      case response do
        %{status: status} when status in [200, 204] -> :ok
        %{status: 403} -> {:error, :access_denied}
        %{status: status} when is_integer(status) -> {:error, {:s3_status, status}}
        _ -> {:error, :invalid_s3_response}
      end
    end
  end

  defp condition(_key, :not_found, _opts), do: {:ok, :not_found}

  defp condition(key, {:token, token}, opts) when is_binary(token) and byte_size(token) > 0 do
    case decode_token(token, key, opts) do
      {:ok, etag} -> {:ok, {:token, etag}}
      :error -> {:error, :invalid_condition}
    end
  end

  defp condition(key, expected, opts) when is_binary(expected) do
    case get(key, opts) do
      {:ok, ^expected, token} -> condition(key, {:token, token}, opts)
      {:ok, _other, _token} -> {:error, :conflict}
      {:error, :not_found} -> {:error, :conflict}
      {:error, reason} -> {:error, reason}
    end
  end

  defp condition(_key, _expected, _opts), do: {:error, :invalid_condition}

  defp conditional_put(key, :not_found, value, opts),
    do: write(key, %{"if-none-match" => "*"}, value, opts)

  defp conditional_put(key, {:token, token}, value, opts),
    do: write(key, %{"if-match" => token}, value, opts)

  defp write(key, headers, value, opts) do
    checksum = :crypto.hash(:sha256, value) |> Base.encode64()
    headers = Map.put(headers, "x-amz-checksum-sha256", checksum)

    case request(:put, key, headers, value, opts) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: 412, code: "PreconditionFailed"}} ->
        if conditional?(headers),
          do: {:error, :conflict},
          else: {:error, {:indeterminate, :unexpected_precondition}}

      {:ok, %{status: 409, code: "ConditionalRequestConflict"}} ->
        if conditional?(headers),
          do: {:error, :conflict},
          else: {:error, {:indeterminate, :unexpected_precondition}}

      {:ok, %{status: 404, code: "NoSuchKey"}} ->
        if Map.has_key?(headers, "if-match"),
          do: {:error, :conflict},
          else: {:error, {:indeterminate, :missing_object}}

      {:ok, %{status: 403}} ->
        {:error, {:indeterminate, :access_denied}}

      {:ok, %{status: status}} when is_integer(status) ->
        {:error, {:indeterminate, {:s3_status, status}}}

      {:ok, _response} ->
        {:error, {:indeterminate, :invalid_s3_response}}

      {:error, {:rejected, _reason}} = error ->
        error

      {:error, {:indeterminate, _reason}} = error ->
        error

      {:error, reason} ->
        {:error, {:indeterminate, reason}}
    end
  end

  defp preflight(key, value, opts) do
    with :ok <- validate_options(opts),
         :ok <- validate_key(key, opts) do
      if byte_size(value) <= @max_object_bytes,
        do: :ok,
        else: {:error, {:rejected, :object_too_large}}
    end
  end

  defp read_object(%{body: body} = response, key, opts) when is_binary(body) do
    headers = Map.get(response, :headers)
    etag = header(headers, "etag")
    checksum = header(headers, "x-amz-checksum-sha256")

    expected_checksum = :crypto.hash(:sha256, body) |> Base.encode64()

    cond do
      byte_size(body) > @max_object_bytes ->
        {:error, :object_too_large}

      not (is_binary(etag) and byte_size(etag) > 0) ->
        {:error, :missing_etag}

      not is_binary(checksum) ->
        {:error, :missing_checksum}

      checksum != expected_checksum ->
        {:error, :checksum_mismatch}

      true ->
        {:ok, body, encode_token(etag, key, opts)}
    end
  end

  defp read_object(_response, _key, _opts), do: {:error, :invalid_s3_response}

  defp request(method, key, headers, body, opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

    request = %{
      method: method,
      bucket: Keyword.fetch!(opts, :bucket),
      key: object_key(key, opts),
      headers: headers,
      body: body,
      timeout_ms: timeout_ms,
      retry: false,
      follow_redirects: false
    }

    request_fn = Keyword.fetch!(opts, :request_fn)
    caller = self()
    reply_ref = make_ref()

    {pid, monitor} =
      spawn_monitor(fn ->
        reply =
          try do
            request_fn.(request)
          rescue
            _error -> {:error, :request_failed}
          catch
            _, _reason -> {:error, :request_failed}
          end

        send(caller, {reply_ref, reply})
      end)

    receive do
      {^reply_ref, reply} ->
        Process.demonitor(monitor, [:flush])
        normalize_reply(reply)

      {:DOWN, ^monitor, :process, ^pid, _reason} ->
        receive do
          {^reply_ref, reply} -> normalize_reply(reply)
        after
          0 -> {:error, :request_failed}
        end
    after
      timeout_ms ->
        Process.exit(pid, :kill)
        Process.demonitor(monitor, [:flush])

        receive do
          {^reply_ref, _reply} -> :ok
        after
          0 -> :ok
        end

        {:error, :timeout}
    end
  end

  defp object_key(key, opts) do
    Keyword.get(opts, :prefix, "jido/") <> "k_" <> Base.url_encode64(key, padding: false)
  end

  defp token_scope(key, opts) do
    :erlang.term_to_binary({opts[:bucket], object_key(key, opts)})
    |> Base.url_encode64(padding: false)
  end

  defp encode_token(etag, key, opts) do
    token_scope(key, opts) <> ":" <> Base.url_encode64(etag, padding: false)
  end

  defp decode_token(token, key, opts) do
    case :binary.split(token, ":") do
      [scope, encoded_etag] ->
        with true <- scope == token_scope(key, opts),
             {:ok, etag} <- Base.url_decode64(encoded_etag, padding: false),
             true <- byte_size(etag) > 0 do
          {:ok, etag}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp conditional?(headers) do
    Map.has_key?(headers, "if-match") or Map.has_key?(headers, "if-none-match")
  end

  defp validate_key(key, opts) do
    if byte_size(object_key(key, opts)) <= 1_024,
      do: :ok,
      else: {:error, :object_key_too_long}
  end

  defp normalize_reply({:ok, %{} = response}), do: {:ok, response}
  defp normalize_reply({:error, _reason} = error), do: error
  defp normalize_reply(_reply), do: {:error, :invalid_s3_response}

  defp header(headers, wanted) when is_map(headers) or is_list(headers) do
    Enum.find_value(headers, fn
      {name, value} when is_binary(name) and is_binary(value) ->
        if String.downcase(name) == wanted, do: value

      _ ->
        nil
    end)
  end

  defp header(_headers, _wanted), do: nil

  defp valid_prefix?(prefix), do: is_binary(prefix) and String.valid?(prefix)

  defp valid_timeout?(timeout),
    do: is_integer(timeout) and timeout > 0 and timeout <= @max_timeout_ms
end
