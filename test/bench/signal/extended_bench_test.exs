Code.require_file("../../../bench/signal/support/suite.exs", __DIR__)

defmodule JidoTest.Bench.Signal.ExtendedBenchTest do
  use ExUnit.Case, async: false
  @moduletag :bench
  alias Jido.Bench.Signal.{Measure, Suite}

  test "the smoke inventory includes each reviewed gap" do
    workloads = Suite.workloads("smoke")
    names = Enum.map(workloads, & &1.name)

    for name <- ~w(signal/typed signal/typed_invalid signal/invalid
                   trace/put trace/get trace/child context/put
                   serialization/base64/encode serialization/base64/decode
                   serialization/nested/encode serialization/nested/decode
                   serialization/batch/json/encode serialization/batch/json/decode
                   serialization/batch/erlang_term/encode serialization/batch/erlang_term/decode
                   serialization/invalid_json serialization/invalid_term
                   serialization/invalid_base64 serialization/oversized
                   router/wildcard_build router/wildcard_many router/deep
                   router/add router/remove router/merge
                   dispatch/dead_pid dispatch/timeout
                   bus/fanout_processes bus/concurrent_publish bus/sustained_publish
                   bus/backlog_publish bus/backlog_drain bus/large_replay
                   bus/large_replay_filtered bus/durable_reconnect
                   bus/invalid_signal bus/store_full bus/store_failure
                   router/selector_source_hit router/selector_source_miss
                   router/selector_subject_hit router/selector_subject_miss
                   router/selector_source_subject_hit router/selector_source_subject_miss
                   bus/selector_hit bus/selector_miss bus/selector_churn) do
      assert name in names, "missing benchmark: #{name}"
    end

    ids = Enum.map(workloads, & &1.id)
    assert length(ids) == length(Enum.uniq(ids))
  end

  test "every added workload passes timing, result checks, and resource cleanup" do
    for workload <- Suite.extra_workloads(2) do
      assert length(Measure.timing(workload, 1, 1).wall_ns.samples) == 1
      resources = Measure.resources(workload)
      assert resources.owned_remaining == 0

      if workload.name == "bus/fanout_processes" do
        assert workload.dimensions.consumers == 2
        assert resources.owned_process_starts >= 4
      end

      if workload.name == "bus/backlog_publish" do
        assert resources.observed_peak.mailbox_messages >= workload.dimensions.records
      end

      if String.starts_with?(workload.name, "bus/selector_") do
        assert resources.owned_process_starts >= 2
      end
    end
  end

  test "raw binary fixtures force Base64 and batch dimensions increase with size" do
    workloads = Suite.extra_workloads(2)
    binary = Enum.find(workloads, &(&1.name == "serialization/base64/encode"))
    refute String.valid?(binary.retained.data)
    assert Map.has_key?(Jido.Signal.Codec.to_map(binary.retained), "data_base64")

    for size <- [2, 8, 32] do
      cases = Suite.extra_workloads(size)
      batch = Enum.find(cases, &(&1.name == "serialization/batch/json/encode"))
      assert batch.dimensions.records == size
      wildcard = Enum.find(cases, &(&1.name == "router/wildcard_many"))
      assert wildcard.dimensions.wildcard_routes == size * 16
      paths = Jido.Bench.Signal.RouterCases.wildcard_specs(size * 16) |> Enum.map(&elem(&1, 0))
      assert length(Enum.uniq(paths)) == size * 16
      replay = Enum.find(cases, &(&1.name == "bus/large_replay"))
      assert replay.dimensions.records == size * 256
    end
  end

  test "growth checks record valid fixture heap measurements without thresholds" do
    checks = Suite.check_growth!()
    assert length(checks) == 2
    assert Enum.all?(checks, &(&1.small_flat_bytes > 0 and &1.large_flat_bytes > 0 and &1.ratio > 0))
    assert_raise ArgumentError, fn -> Suite.extra_workloads(1) end
  end

  test "selector workloads scale candidates and reject incorrect lookup and delivery results" do
    for size <- [2, 8, 32] do
      cases = Suite.extra_workloads(size)
      lookup = Enum.find(cases, &(&1.name == "router/selector_source_subject_hit"))
      assert lookup.dimensions.type_candidates == size * 128
      assert lookup.dimensions.matching_subscriptions == 1
      publication = Enum.find(cases, &(&1.name == "bus/selector_miss"))
      assert publication.dimensions.subscriptions == size * 16
      assert publication.dimensions.matching_subscriptions == 0
    end

    cases = Suite.extra_workloads(2)
    lookup = Enum.find(cases, &(&1.name == "router/selector_source_subject_hit"))
    assert_raise RuntimeError, ~r/incorrect result/, fn -> lookup.check.([], nil) end
    miss = Enum.find(cases, &(&1.name == "router/selector_source_subject_miss"))
    assert_raise RuntimeError, ~r/incorrect result/, fn -> miss.check.(["extra"], nil) end

    publication = Enum.find(cases, &(&1.name == "bus/selector_miss"))
    state = publication.setup.(%{})

    try do
      records = publication.run.(state)
      send(self(), {:signal, publication.retained})

      assert_raise RuntimeError, ~r/unexpected Signal/, fn ->
        publication.check.(records, state)
      end
    after
      publication.cleanup.(state)
    end
  end
end
