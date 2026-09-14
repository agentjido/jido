defmodule JidoTest.Persistence.S3Test do
  use ExUnit.Case, async: true

  alias Jido.Persistence.S3

  setup do
    {:ok, store} = Elixir.Agent.start_link(fn -> %{} end)
    on_exit(fn -> if Process.alive?(store), do: Elixir.Agent.stop(store) end)
    %{store: store, opts: [bucket: "jido-test", prefix: "case/", request_fn: client(store)]}
  end

  test "binary key mapping, checksums, token CAS, and byte CAS", c do
    keys = ["", <<0, 255>>, "AA"]

    for key <- keys do
      assert {:error, :not_found} = S3.get(key, c.opts)
      assert :ok = S3.compare_and_swap(key, :not_found, <<0, 255>>, c.opts)
      assert {:ok, <<0, 255>>, token} = S3.get(key, c.opts)
      assert is_binary(token)

      assert {:error, {:rejected, :invalid_condition}} =
               S3.compare_and_swap(key <> "other", {:token, token}, "wrong-key", c.opts)

      assert {:error, {:rejected, :invalid_condition}} =
               S3.compare_and_swap(key, {:token, "malformed"}, "bad-token", c.opts)

      assert {:error, :conflict} = S3.compare_and_swap(key, :not_found, "wrong", c.opts)
      assert {:error, :conflict} = S3.compare_and_swap(key, "wrong", "wrong", c.opts)
      assert :ok = S3.compare_and_swap(key, {:token, token}, "second", c.opts)
      assert {:error, :conflict} = S3.compare_and_swap(key, {:token, token}, "stale", c.opts)
      assert :ok = S3.compare_and_swap(key, "second", "third", c.opts)
      assert {:ok, "third", _token} = S3.get(key, c.opts)
    end

    stored = Elixir.Agent.get(c.store, & &1)
    assert map_size(stored) == length(keys)
    assert Map.keys(stored) |> Enum.uniq() |> length() == length(keys)
    assert Enum.all?(Map.keys(stored), &String.starts_with?(&1, "case/k_"))
  end

  test "only one conditional create or update wins", c do
    results =
      1..4
      |> Task.async_stream(
        fn i -> S3.compare_and_swap("same", :not_found, <<i>>, c.opts) end,
        max_concurrency: 4
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &(&1 == :ok)) == 1
    assert Enum.count(results, &(&1 == {:error, :conflict})) == 3

    assert {:ok, _bytes, token} = S3.get("same", c.opts)

    results =
      1..4
      |> Task.async_stream(
        fn i -> S3.compare_and_swap("same", {:token, token}, <<i + 10>>, c.opts) end,
        max_concurrency: 4
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &(&1 == :ok)) == 1
    assert Enum.count(results, &(&1 == {:error, :conflict})) == 3

    assert {:ok, _bytes, stale} = S3.get("same", c.opts)
    assert :ok = S3.delete("same", c.opts)
    assert {:error, :conflict} = S3.compare_and_swap("same", {:token, stale}, "old", c.opts)
    assert {:error, :not_found} = S3.get("same", c.opts)
  end

  test "token updates use one conditional PUT without another GET", c do
    owner = self()
    client = Keyword.fetch!(c.opts, :request_fn)

    opts =
      Keyword.put(c.opts, :request_fn, fn request ->
        send(owner, {:s3_request, request})
        client.(request)
      end)

    assert :ok = S3.compare_and_swap("requests", :not_found, "first", opts)
    assert_receive {:s3_request, create}
    assert %{method: :put, retry: false, follow_redirects: false} = create
    assert create.headers["if-none-match"] == "*"
    checksum = :crypto.hash(:sha256, "first") |> Base.encode64()
    assert create.headers["x-amz-checksum-sha256"] == checksum

    refute_received {:s3_request, _}

    assert {:ok, "first", token} = S3.get("requests", opts)
    assert_receive {:s3_request, read}
    assert read.method == :get
    assert read.headers["x-amz-checksum-mode"] == "ENABLED"
    refute_received {:s3_request, _}

    assert :ok = S3.compare_and_swap("requests", {:token, token}, "second", opts)
    assert_receive {:s3_request, update}
    assert update.method == :put
    assert is_binary(update.headers["if-match"])
    assert update.headers["if-match"] != ""
    refute_received {:s3_request, _}

    assert :ok = S3.compare_and_swap("requests", "second", "third", opts)
    assert_receive {:s3_request, byte_read}
    assert byte_read.method == :get
    assert_receive {:s3_request, byte_update}
    assert byte_update.method == :put
    assert is_binary(byte_update.headers["if-match"])
    refute_received {:s3_request, _}
  end

  test "read errors distinguish missing objects and reject corrupt data", c do
    read = fn response -> Keyword.put(c.opts, :request_fn, fn _ -> response end) end

    assert {:error, :not_found} = S3.get("key", read.({:ok, %{status: 404, code: "NoSuchKey"}}))

    assert {:error, :missing_bucket} =
             S3.get("key", read.({:ok, %{status: 404, code: "NoSuchBucket"}}))

    assert {:error, :not_found} =
             S3.get(
               "key",
               read.({:ok, %{status: 404, headers: %{"x-amz-delete-marker" => "true"}}})
             )

    assert {:error, :access_denied} = S3.get("key", read.({:ok, %{status: 403}}))
    assert {:error, {:s3_status, 404}} = S3.get("key", read.({:ok, %{status: 404}}))

    assert {:error, :missing_etag} =
             S3.get("key", read.({:ok, %{status: 200, body: "x", headers: %{}}}))

    assert {:error, :missing_checksum} =
             S3.get("key", read.({:ok, %{status: 200, body: "x", headers: %{"etag" => "v"}}}))

    assert {:error, :checksum_mismatch} =
             S3.get(
               "key",
               read.(
                 {:ok,
                  %{
                    status: 200,
                    body: "x",
                    headers: %{"etag" => "v", "x-amz-checksum-sha256" => "bad"}
                  }}
               )
             )

    assert {:error, :invalid_s3_response} = S3.get("key", read.(:invalid))
  end

  test "write errors keep only documented conflicts and prewrite rejection certain", c do
    request = fn reply -> Keyword.put(c.opts, :request_fn, fn _ -> reply end) end

    assert {:error, :conflict} =
             S3.compare_and_swap(
               "key",
               :not_found,
               "value",
               request.({:ok, %{status: 412, code: "PreconditionFailed"}})
             )

    assert {:error, :conflict} =
             S3.compare_and_swap(
               "key",
               :not_found,
               "value",
               request.({:ok, %{status: 409, code: "ConditionalRequestConflict"}})
             )

    assert {:error, {:indeterminate, {:s3_status, 412}}} =
             S3.compare_and_swap("key", :not_found, "value", request.({:ok, %{status: 412}}))

    assert {:error, {:indeterminate, {:s3_status, 404}}} =
             S3.compare_and_swap(
               "key",
               :not_found,
               "value",
               request.({:ok, %{status: 404, code: "NoSuchBucket"}})
             )

    assert {:error, {:rejected, :bad_request}} =
             S3.compare_and_swap(
               "key",
               :not_found,
               "value",
               request.({:error, {:rejected, :bad_request}})
             )

    assert {:error, {:indeterminate, :lost_reply}} =
             S3.compare_and_swap(
               "key",
               :not_found,
               "value",
               request.({:error, {:indeterminate, :lost_reply}})
             )

    assert {:error, {:indeterminate, :invalid_s3_response}} =
             S3.compare_and_swap("key", :not_found, "value", request.(:invalid))
  end

  test "a lost write reply is not retried or turned into a conflict", c do
    {:ok, calls} = Elixir.Agent.start_link(fn -> 0 end)
    on_exit(fn -> if Process.alive?(calls), do: Elixir.Agent.stop(calls) end)
    client = Keyword.fetch!(c.opts, :request_fn)

    lost = fn request ->
      Elixir.Agent.update(calls, &(&1 + 1))
      assert {:ok, %{status: 200}} = client.(request)
      {:error, {:indeterminate, :lost_reply}}
    end

    opts = Keyword.put(c.opts, :request_fn, lost)

    assert {:error, {:indeterminate, :lost_reply}} =
             S3.compare_and_swap("lost", :not_found, "saved", opts)

    assert Elixir.Agent.get(calls, & &1) == 1
    assert {:ok, "saved", _token} = S3.get("lost", c.opts)
  end

  test "configuration, key length, object size, and request duration are bounded", c do
    assert {:error, :invalid_bucket} = S3.validate_options(request_fn: fn _ -> :ok end)
    assert {:error, :invalid_request_fn} = S3.validate_options(bucket: "test")
    assert {:error, :unknown_option} = S3.validate_options(c.opts ++ [endpoint: "other"])
    assert {:error, :duplicate_option} = S3.validate_options(c.opts ++ [bucket: "other"])

    assert {:error, :invalid_timeout} =
             S3.validate_options(Keyword.put(c.opts, :timeout_ms, :infinity))

    assert {:error, {:rejected, :object_too_large}} =
             S3.compare_and_swap("key", :not_found, :binary.copy("x", 5_000_001), c.opts)

    assert {:error, {:rejected, :object_key_too_long}} =
             S3.compare_and_swap(:binary.copy("x", 1_000), :not_found, "x", c.opts)

    blocked =
      Keyword.merge(c.opts,
        timeout_ms: 10,
        request_fn: fn _ ->
          receive do
            :never -> :ok
          end
        end
      )

    assert {:error, :timeout} = S3.get("key", blocked)

    assert {:error, {:indeterminate, :timeout}} =
             S3.compare_and_swap("key", :not_found, "x", blocked)
  end

  defp client(store) do
    fn request ->
      case request.method do
        :get ->
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

        :put ->
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

        :delete ->
          Elixir.Agent.get_and_update(store, fn values ->
            {{:ok, %{status: 204}}, Map.delete(values, request.key)}
          end)
      end
    end
  end
end
