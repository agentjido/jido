defmodule JidoTest.System.Services.MinIO do
  @moduledoc false

  import ExUnit.Assertions
  alias Bedrock.ObjectStorage

  def start_s3!(on_exit) do
    endpoint = required!("JIDO_SYSTEM_MINIO_URL") |> URI.parse()

    unless endpoint.scheme in ["http", "https"] and is_binary(endpoint.host) and
             endpoint.path in [nil, "", "/"] do
      raise "JIDO_SYSTEM_MINIO_URL must be an explicit S3-compatible endpoint without a path"
    end

    config = [
      scheme: endpoint.scheme <> "://",
      host: endpoint.host,
      port: endpoint.port,
      access_key_id: required!("JIDO_SYSTEM_MINIO_ACCESS_KEY"),
      secret_access_key: required!("JIDO_SYSTEM_MINIO_SECRET_KEY"),
      region: "us-east-1",
      http_client: ExAws.Request.Req,
      retries: [max_attempts: 1],
      debug_requests: false,
      s3: [scheme: endpoint.scheme <> "://", host: endpoint.host, port: endpoint.port]
    ]

    bucket = "jido-system-" <> Base.encode16(:crypto.strong_rand_bytes(10), case: :lower)
    assert {:ok, _} = ExAws.S3.put_bucket(bucket, "us-east-1") |> ExAws.request(config)
    backend = ObjectStorage.backend(ObjectStorage.S3, bucket: bucket, config: config)

    on_exit.(fn ->
      keys = ObjectStorage.list(backend, "") |> Enum.to_list()
      for key <- keys, do: assert(:ok == ObjectStorage.delete(backend, key))
      assert Enum.to_list(ObjectStorage.list(backend, "")) == []
      assert {:ok, _} = ExAws.S3.delete_bucket(bucket) |> ExAws.request(config)
    end)

    {Jido.Persistence.S3, bucket: bucket, prefix: "system/", timeout_ms: 10_000, request_fn: &s3_request(&1, config)}
  end

  def configured? do
    Enum.all?(
      ~w(JIDO_SYSTEM_MINIO_URL JIDO_SYSTEM_MINIO_ACCESS_KEY JIDO_SYSTEM_MINIO_SECRET_KEY),
      &(is_binary(System.get_env(&1)) and System.get_env(&1) != "")
    )
  end

  defp s3_request(request, config) do
    operation = %ExAws.Operation.S3{
      http_method: request.method,
      bucket: request.bucket,
      path: request.key,
      headers: request.headers,
      body: request.body || ""
    }

    config =
      Keyword.merge(config,
        retries: [max_attempts: 1, client_error_max_attempts: 1],
        http_opts: [recv_timeout: request.timeout_ms, follow_redirect: false]
      )

    case ExAws.request(operation, config) do
      {:ok, %{status_code: status, headers: headers, body: body}} ->
        {:ok, %{status: status, headers: headers, body: body}}

      {:error, {:http_error, status, %{body: body, headers: headers}}} ->
        {:ok, %{status: status, code: error_code(body), headers: headers, body: body}}

      {:error, {:http_error, status, body}} when is_binary(body) ->
        {:ok, %{status: status, code: error_code(body), headers: [], body: body}}

      {:error, _reason} ->
        {:error, {:indeterminate, :request_failed}}
    end
  end

  defp error_code(body) when is_binary(body) do
    case Regex.run(~r/<Code>([^<]+)<\/Code>/, body) do
      [_match, code] -> code
      _other -> nil
    end
  end

  defp error_code(_body), do: nil

  defp required!(key), do: System.fetch_env!(key)
end
