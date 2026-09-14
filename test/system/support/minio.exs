defmodule JidoTest.System.MinIO do
  @moduledoc false
  import ExUnit.Assertions
  alias Bedrock.ObjectStorage

  def start!(observer, on_exit) do
    {bucket, config} = start_bucket!(observer, on_exit)
    ObjectStorage.backend(ObjectStorage.S3, bucket: bucket, config: config)
  end

  def start_s3!(observer, on_exit) do
    {bucket, config} = start_bucket!(observer, on_exit)

    {:ok, counter} =
      Agent.start(fn -> %{s3_get_requests: 0, s3_put_requests: 0, s3_delete_requests: 0} end)

    on_exit.(fn ->
      JidoTest.System.Observability.measure(observer, Agent.get(counter, & &1))
      Agent.stop(counter)
    end)

    {Jido.Persistence.S3,
     bucket: bucket,
     prefix: "system/",
     timeout_ms: 10_000,
     request_fn: fn request ->
       key = request_count_key(request.method)
       Agent.update(counter, &Map.update!(&1, key, fn count -> count + 1 end))
       s3_request(request, config)
     end}
  end

  defp request_count_key(:get), do: :s3_get_requests
  defp request_count_key(:put), do: :s3_put_requests
  defp request_count_key(:delete), do: :s3_delete_requests

  defp start_bucket!(observer, on_exit) do
    endpoint = required!("JIDO_SYSTEM_MINIO_URL") |> URI.parse()

    unless endpoint.scheme in ["http", "https"] and is_binary(endpoint.host) and
             endpoint.path in [nil, "", "/"],
           do:
             raise(
               "JIDO_SYSTEM_MINIO_URL must be an explicit S3-compatible endpoint without a path"
             )

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
      # Only the bucket created by this exact test is in cleanup scope.
      for key <- keys, do: assert(:ok == ObjectStorage.delete(backend, key))
      assert Enum.to_list(ObjectStorage.list(backend, "")) == []
      assert {:ok, _} = ExAws.S3.delete_bucket(bucket) |> ExAws.request(config)

      assert {:error, {:http_error, 404, _}} =
               ExAws.S3.head_bucket(bucket) |> ExAws.request(config)

      JidoTest.System.Observability.service_log(
        observer,
        :minio,
        "Owned bucket and objects removed",
        %{object_count: length(keys)}
      )
    end)

    JidoTest.System.Observability.service_log(
      observer,
      :minio,
      "Test bucket created; S3 request succeeded"
    )

    {bucket, config}
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
      _ -> nil
    end
  end

  defp error_code(_body), do: nil

  defp required!(key) do
    case System.get_env(key) do
      value when is_binary(value) and value != "" -> value
      _ -> raise "MinIO profile requires #{key}; use a dedicated test service and credentials"
    end
  end
end
