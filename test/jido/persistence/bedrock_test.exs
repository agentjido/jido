defmodule JidoTest.Persistence.BedrockTest do
  use ExUnit.Case, async: false

  alias Jido.Persistence
  alias Jido.Persistence.Bedrock
  alias JidoTest.BedrockRepo
  alias JidoTest.Persistence.AdapterConformance

  @prefix "jido-test/"
  @abort_message "Transaction retry limit exceeded after 0 attempts. Last error: :aborted"

  setup do
    start_supervised!(BedrockRepo)
    opts = [repo: BedrockRepo, prefix: @prefix, timeout_in_ms: 2_000]
    {:ok, opts: opts}
  end

  test "obeys the shared binary get and exact-byte CAS contract", %{opts: opts} do
    assert :ok = AdapterConformance.assert_binary_get_and_cas(Bedrock, opts, :bedrock)
  end

  test "supports unconditional maintenance writes and physical deletes", %{opts: opts} do
    assert :ok = Bedrock.put("key", <<0, 255>>, opts)
    assert {:ok, <<0, 255>>} = Bedrock.get("key", opts)
    assert :ok = Bedrock.delete("key", opts)
    assert {:error, :not_found} = Bedrock.get("key", opts)
  end

  test "uses the prefix and safe transaction options", %{opts: opts} do
    assert :ok = Bedrock.put("key", "value", opts)
    assert BedrockRepo.values() == %{(@prefix <> "key") => "value"}
    assert [write_opts] = BedrockRepo.transaction_options()
    assert write_opts == [retry_limit: 0, timeout_in_ms: 2_000]

    BedrockRepo.reset()
    assert {:error, :not_found} = Bedrock.get("key", opts)
    assert [read_opts] = BedrockRepo.transaction_options()
    assert read_opts == [timeout_in_ms: 2_000]
  end

  test "validates the Bedrock repo and all adapter options", %{opts: opts} do
    assert :ok = Bedrock.validate_options(opts)
    assert {:ok, {Bedrock, ^opts}} = Persistence.resolve_config({Bedrock, opts}, nil)

    assert {:error, _reason} = Bedrock.validate_options([])
    assert {:error, _reason} = Bedrock.validate_options(repo: String)
    assert {:error, _reason} = Bedrock.validate_options(repo: BedrockRepo, prefix: "")
    assert {:error, _reason} = Bedrock.validate_options(repo: BedrockRepo, prefix: <<255>>)
    assert {:error, _reason} = Bedrock.validate_options(repo: BedrockRepo, timeout_in_ms: 0)
    assert {:error, _reason} = Bedrock.validate_options(repo: BedrockRepo, unknown: true)
    assert {:error, _reason} = Bedrock.validate_options(repo: BedrockRepo, repo: BedrockRepo)
    assert {:error, _reason} = Bedrock.validate_options([:not_keyword])
  end

  test "rejects Bedrock size limits before a transaction starts", %{opts: opts} do
    oversized_key = :binary.copy("k", 16 * 1024)
    oversized_value = :binary.copy(<<0>>, 128 * 1024 + 1)

    assert {:error, {:rejected, {:bedrock_key_too_large, _, 16_384}}} =
             Bedrock.compare_and_swap(oversized_key, :not_found, "value", opts)

    assert {:error, {:rejected, {:bedrock_value_too_large, 131_073, 131_072}}} =
             Bedrock.compare_and_swap("key", :not_found, oversized_value, opts)

    assert BedrockRepo.transaction_options() == []
  end

  test "classifies all unknown write outcomes as indeterminate", %{opts: opts} do
    for mode <- [
          {:return, {:error, :unavailable}},
          {:return, {:error, :conflict}},
          {:return, :unexpected},
          {:raise, "transaction failed"}
        ] do
      BedrockRepo.fail_next(mode)

      assert {:error, {:indeterminate, _reason}} =
               Bedrock.compare_and_swap("key", :not_found, "value", opts)
    end
  end

  test "does not report conflict when a commit reply is lost", %{opts: opts} do
    BedrockRepo.fail_next({:after_commit, {:error, :timeout}})

    assert {:error, {:indeterminate, _reason}} =
             Bedrock.compare_and_swap("key", :not_found, "stored", opts)

    assert {:ok, "stored"} = Bedrock.get("key", opts)
  end

  test "maps the Bedrock zero-retry resolver abort to a confirmed conflict", %{opts: opts} do
    BedrockRepo.fail_next({:raise, @abort_message})

    assert {:error, :conflict} =
             Bedrock.compare_and_swap("key", :not_found, "value", opts)

    assert BedrockRepo.values() == %{}
  end

  test "reports invalid stored values without changing them", %{opts: opts} do
    BedrockRepo.fail_next({:after_commit, :ok})
    assert {:error, {:indeterminate, _reason}} = Bedrock.put("key", "value", opts)

    values = BedrockRepo.values()
    storage_key = @prefix <> "key"
    Agent.update(BedrockRepo, &put_in(&1.values[storage_key], :not_binary))

    assert {:error, {:invalid_bedrock_value, :not_binary}} = Bedrock.get("key", opts)

    assert {:error, {:indeterminate, _reason}} =
             Bedrock.compare_and_swap("key", "value", "new", opts)

    assert Map.put(values, storage_key, :not_binary) == BedrockRepo.values()
  end
end
