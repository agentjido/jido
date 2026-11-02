defmodule Jido.AI.Telemetry.CorrelationStoreTest do
  use Covenant.Case, component: "jido_ai.observability", async: false

  @moduletag obligation: [
               "jido_ai.observability.I1",
               "jido_ai.observability.I4",
               "jido_ai.observability.I5"
             ]

  alias Jido.AI.Telemetry.CorrelationStore

  defmodule CleanupProbe do
    def expire(key, {owner, value}) do
      send(owner, {:expired_correlation, key, value})
      :ok
    end

    def fail(_key, _value), do: raise("cleanup failed")
  end

  test "put, get, and take use a keyed active record" do
    key = unique_key(:active)

    assert :ok = CorrelationStore.put(key, %{status: :active})
    assert %{status: :active} = CorrelationStore.get(key)
    assert %{status: :active} = CorrelationStore.take(key)
    assert is_nil(CorrelationStore.get(key))
    assert is_nil(CorrelationStore.take(key))
  end

  test "put_new permits one concurrent owner" do
    key = unique_key(:put_new)

    results =
      1..32
      |> Task.async_stream(
        fn value -> {value, CorrelationStore.put_new(key, value)} end,
        max_concurrency: 32,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert [{winner, true}] = Enum.filter(results, &elem(&1, 1))
    assert winner == CorrelationStore.take(key)
  end

  test "prune_stale removes records, runs cleanup, and emits a bounded event" do
    key = unique_key(:stale)
    handler_id = "jido-ai-correlation-cleanup-#{System.unique_integer([:positive])}"

    assert :ok =
             :telemetry.attach(
               handler_id,
               [:jido, :ai, :telemetry, :correlation, :cleanup],
               fn event, measurements, metadata, owner ->
                 send(owner, {:telemetry, event, measurements, metadata})
               end,
               self()
             )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert CorrelationStore.put_new(key, {self(), :value}, on_expire: {CleanupProbe, :expire})

    assert CorrelationStore.prune_stale(0) >= 1
    assert is_nil(CorrelationStore.get(key))
    assert_receive {:expired_correlation, ^key, :value}

    assert_receive {:telemetry, [:jido, :ai, :telemetry, :correlation, :cleanup], %{expired: expired, size: size}, %{}}

    assert expired >= 1
    assert is_integer(size) and size >= 0
  end

  test "cleanup failures do not affect the runtime" do
    key = unique_key(:cleanup_failure)

    assert CorrelationStore.put_new(key, :value, on_expire: {CleanupProbe, :fail})
    assert CorrelationStore.prune_stale(0) >= 1
    assert is_nil(CorrelationStore.get(key))
  end

  defp unique_key(label) do
    {:test, label, System.unique_integer([:positive])}
  end
end
