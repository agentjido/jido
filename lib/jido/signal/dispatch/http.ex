defmodule Jido.Signal.Dispatch.Http do
  @moduledoc """
  Delivers one Signal as a structured CloudEvents JSON request.

  The adapter uses OTP `:httpc`. It sends a synchronous `POST` request and
  treats each 2xx response as success. Redirects are disabled. Dispatch does
  not add a retry loop.

  Use `Jido.Signal.Dispatch.dispatch/2` so Dispatch can prepare and validate
  the target before delivery:

      Jido.Signal.Dispatch.dispatch(signal,
        {:http,
         url: "https://api.example.com/events",
         headers: [{"authorization", "Bearer token"}],
         timeout: 5_000}
      )

  OTP `:httpc` can honor `Retry-After` on a 503 response. OTP 27 has no option
  to disable this client behavior. The caller owns all other concurrency,
  retry, rate-limit, and circuit-breaker policy.

  Treat the URL as trusted application configuration. The adapter permits
  private network targets and does not protect against DNS rebinding. OTP 27
  `:httpc` also has no response body size limit for non-streamed responses. Use
  a custom adapter for untrusted targets or a strict response size limit.

  Applications that need a different HTTP method, custom TLS policy, response
  data, or request signing must use a custom Dispatch adapter.
  """

  @behaviour Jido.Signal.Dispatch.Adapter

  alias Jido.Signal.Serialization

  @content_type ~c"application/cloudevents+json"
  @default_timeout 5_000
  @max_timeout 60_000
  @max_url_bytes 8_192
  @max_header_count 32
  @max_header_name_bytes 128
  @max_header_value_bytes 8_192
  @max_headers_bytes 64_000
  @header_name_pattern ~r/\A[!#$%&'*+\-.^_`|~0-9A-Za-z]+\z/
  @header_value_control_pattern ~r/[\x00-\x1F\x7F]/
  @url_unsafe_pattern ~r/[\x00-\x20\x7F]/
  @reserved_headers MapSet.new([
                      "connection",
                      "content-encoding",
                      "content-length",
                      "content-type",
                      "expect",
                      "host",
                      "proxy-connection",
                      "te",
                      "trailer",
                      "transfer-encoding",
                      "upgrade"
                    ])

  @header_schema Zoi.tuple({Zoi.string(), Zoi.string()})
                 |> Zoi.refine({__MODULE__, :validate_header, []})

  @headers_schema Zoi.list(@header_schema)
                  |> Zoi.refine({__MODULE__, :validate_headers, []})

  @options_schema Zoi.keyword(
                    [
                      url:
                        Zoi.string()
                        |> Zoi.refine({__MODULE__, :validate_url, []})
                        |> Zoi.required(),
                      headers: @headers_schema |> Zoi.default([]),
                      timeout:
                        Zoi.integer()
                        |> Zoi.min(1)
                        |> Zoi.max(@max_timeout)
                        |> Zoi.default(@default_timeout)
                    ],
                    unrecognized_keys: :error
                  )

  @type header :: {String.t(), String.t()}
  @type delivery_opts :: [
          url: String.t(),
          headers: [header()],
          timeout: pos_integer()
        ]
  @type delivery_error ::
          :timeout
          | {:http_status, non_neg_integer()}
          | {:serialization, term()}
          | {:transport, term()}

  @impl Jido.Signal.Dispatch.Adapter
  def options_schema, do: @options_schema

  @impl Jido.Signal.Dispatch.Adapter
  @spec deliver(Jido.Signal.t(), delivery_opts()) :: :ok | {:error, delivery_error()}
  def deliver(signal, opts) do
    with {:ok, body} <- serialize(signal) do
      request(
        Keyword.fetch!(opts, :url),
        Keyword.fetch!(opts, :headers),
        Keyword.fetch!(opts, :timeout),
        body
      )
    end
  end

  @doc false
  def validate_url(url, _context) do
    cond do
      not String.valid?(url) ->
        {:error, "must be valid UTF-8"}

      byte_size(url) > @max_url_bytes ->
        {:error, "must be at most #{@max_url_bytes} bytes"}

      not ascii?(url) ->
        {:error, "must use ASCII with percent-encoding for non-ASCII values"}

      Regex.match?(@url_unsafe_pattern, url) ->
        {:error, "must not contain whitespace or control characters"}

      true ->
        validate_uri(URI.new(url))
    end
  end

  @doc false
  def validate_header({name, value}, _context) do
    cond do
      not String.valid?(name) or not String.valid?(value) ->
        {:error, "must contain valid UTF-8 strings"}

      byte_size(name) > @max_header_name_bytes ->
        {:error, "contains a header name longer than #{@max_header_name_bytes} bytes"}

      byte_size(value) > @max_header_value_bytes ->
        {:error, "contains a header value longer than #{@max_header_value_bytes} bytes"}

      not Regex.match?(@header_name_pattern, name) ->
        {:error, "contains an invalid header name"}

      Regex.match?(@header_value_control_pattern, value) ->
        {:error, "contains an invalid header value"}

      true ->
        validate_header_name(String.downcase(name))
    end
  end

  @doc false
  def validate_headers(headers, _context) do
    normalized_names = Enum.map(headers, fn {name, _value} -> String.downcase(name) end)

    total_bytes =
      Enum.reduce(headers, 0, fn {name, value}, total ->
        total + byte_size(name) + byte_size(value)
      end)

    cond do
      length(headers) > @max_header_count ->
        {:error, "must contain at most #{@max_header_count} headers"}

      length(Enum.uniq(normalized_names)) != length(normalized_names) ->
        {:error, "must not contain duplicate header names"}

      total_bytes > @max_headers_bytes ->
        {:error, "must contain at most #{@max_headers_bytes} bytes"}

      true ->
        :ok
    end
  end

  defp validate_header_name(normalized_name) do
    cond do
      MapSet.member?(@reserved_headers, normalized_name) ->
        {:error, "contains the reserved header #{normalized_name}"}

      String.starts_with?(normalized_name, "ce-") ->
        {:error, "must not contain CloudEvents metadata headers"}

      true ->
        :ok
    end
  end

  defp validate_uri({:ok, %URI{userinfo: userinfo}}) when is_binary(userinfo),
    do: {:error, "must not contain user information"}

  defp validate_uri({:ok, %URI{fragment: fragment}}) when is_binary(fragment),
    do: {:error, "must not contain a fragment"}

  defp validate_uri({:ok, %URI{port: port}})
       when not is_integer(port) or port < 1 or port > 65_535,
       do: {:error, "must contain a port between 1 and 65535"}

  defp validate_uri({:ok, %URI{scheme: scheme, host: host}})
       when scheme in ["http", "https"] and is_binary(host) and host != "",
       do: :ok

  defp validate_uri(_uri), do: {:error, "must be an HTTP or HTTPS URL with a host"}

  defp ascii?(value), do: Enum.all?(:binary.bin_to_list(value), &(&1 < 128))

  defp serialize(signal) do
    case Serialization.serialize(signal, format: :json) do
      {:ok, body} -> {:ok, body}
      {:error, reason} -> {:error, {:serialization, reason}}
    end
  end

  defp request(url, headers, timeout, body) do
    request = {
      String.to_charlist(url),
      Enum.map(headers, fn {name, value} ->
        {String.to_charlist(name), value}
      end),
      @content_type,
      body
    }

    case :httpc.request(
           :post,
           request,
           request_options(url, timeout),
           body_format: :binary,
           full_result: false
         ) do
      {:ok, {status, _body}} when status in 200..299 -> :ok
      {:ok, {status, _body}} -> {:error, {:http_status, status}}
      {:error, :timeout} -> {:error, :timeout}
      {:error, reason} -> {:error, {:transport, reason}}
    end
  end

  defp request_options(url, timeout) do
    options = [timeout: timeout, connect_timeout: timeout, autoredirect: false]

    case URI.parse(url) do
      %URI{scheme: "https"} ->
        Keyword.put(options, :ssl, :httpc.ssl_verify_host_options(true))

      _uri ->
        options
    end
  end
end
