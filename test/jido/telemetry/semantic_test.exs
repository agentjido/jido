defmodule Jido.Telemetry.SemanticTest do
  use ExUnit.Case, async: true

  alias Jido.Telemetry.Semantic

  test "metadata normalization keeps only bounded semantic fields" do
    invalid_utf8 = <<255>>

    assert Semantic.normalize_metadata(%{
             schema_version: 99,
             agent_namespace: "shop",
             agent_partition: "west",
             agent_id: "order-1",
             agent_module: __MODULE__,
             status: :conflict,
             stage: :commit,
             operation: :compare_and_swap,
             error_code: :persistence_callback_failed,
             retryable?: false,
             trace_id: String.duplicate("x", 257),
             signal_type: invalid_utf8,
             partition: %{private: self()},
             raw_error: RuntimeError.exception("private")
           }) == %{
             schema_version: 1,
             agent_namespace: "shop",
             agent_partition: "west",
             agent_id: "order-1",
             agent_module: __MODULE__,
             status: :conflict,
             stage: :commit,
             operation: :compare_and_swap,
             error_code: :persistence_callback_failed,
             retryable?: false
           }

    refute Map.has_key?(
             Semantic.normalize_metadata(%{
               agent_partition: String.duplicate("p", 129)
             }),
             :agent_partition
           )
  end

  test "measurement normalization keeps only approved integers" do
    assert Semantic.normalize_measurements(%{
             system_time: -1,
             duration: 3,
             revision_after: 2,
             queue_depth: 0,
             failed_count: -1,
             ratio: 0.5,
             private_count: 9
           }) == %{
             system_time: -1,
             duration: 3,
             revision_after: 2,
             queue_depth: 0
           }
  end

  test "a returned failure stops a span and an escaping fault reports an exception" do
    handler = {__MODULE__, make_ref()}
    prefix = [:jido, :persistence, :operation]
    events = for ending <- [:start, :stop, :exception], do: prefix ++ [ending]

    :ok =
      :telemetry.attach_many(
        handler,
        events,
        fn event, measurements, metadata, owner ->
          send(owner, {:semantic_event, event, measurements, metadata})
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert {:error, :conflict} =
             Semantic.with_span(prefix, %{operation: :compare_and_swap}, %{}, fn ->
               {:error, :conflict}
             end)

    assert_receive {:semantic_event, [:jido, :persistence, :operation, :start],
                    %{system_time: _, monotonic_time: _}, %{schema_version: 1}}

    assert_receive {:semantic_event, [:jido, :persistence, :operation, :stop],
                    %{duration: duration}, %{status: :conflict}}

    assert duration >= 0

    assert catch_throw(
             Semantic.with_span(prefix, %{operation: :load}, %{}, fn -> throw(:fault) end)
           ) == :fault

    assert_receive {:semantic_event, [:jido, :persistence, :operation, :start], _, _}

    assert_receive {:semantic_event, [:jido, :persistence, :operation, :exception],
                    %{duration: duration}, %{status: :error, kind: :throw}}

    assert duration >= 0
  end
end
