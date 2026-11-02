defmodule JidoTest.Persistence.S3Client do
  @moduledoc false

  def new(store) do
    fn request -> request(store, request) end
  end

  defp request(store, %{method: :get} = request) do
    Elixir.Agent.get(store, fn values ->
      case Map.get(values, request.key) do
        nil ->
          {:ok, %{status: 404, code: "NoSuchKey"}}

        {body, etag} ->
          checksum = :crypto.hash(:sha256, body) |> Base.encode64()

          {:ok,
           %{
             status: 200,
             body: body,
             headers: %{"ETag" => etag, "x-amz-checksum-sha256" => checksum}
           }}
      end
    end)
  end

  defp request(store, %{method: :put} = request) do
    Elixir.Agent.get_and_update(store, fn values ->
      current = Map.get(values, request.key)
      headers = request.headers

      condition =
        cond do
          Map.get(headers, "if-none-match") == "*" ->
            current == nil

          is_binary(Map.get(headers, "if-match")) ->
            current != nil and elem(current, 1) == headers["if-match"]

          true ->
            true
        end

      cond do
        current == nil and Map.has_key?(headers, "if-match") ->
          {{:ok, %{status: 404, code: "NoSuchKey"}}, values}

        not condition ->
          {{:ok, %{status: 412, code: "PreconditionFailed"}}, values}

        headers["x-amz-checksum-sha256"] !=
            :crypto.hash(:sha256, request.body) |> Base.encode64() ->
          {{:ok, %{status: 400, code: "BadDigest"}}, values}

        true ->
          etag = "etag-#{System.unique_integer([:positive])}"
          {{:ok, %{status: 200}}, Map.put(values, request.key, {request.body, etag})}
      end
    end)
  end

  defp request(store, %{method: :delete} = request) do
    Elixir.Agent.get_and_update(store, fn values ->
      {{:ok, %{status: 204}}, Map.delete(values, request.key)}
    end)
  end
end
