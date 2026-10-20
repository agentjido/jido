defmodule JidoTest.Telemetry.PersistenceTest do
  use Covenant.Case, component: "jido.telemetry", async: false

  import ExUnit.CaptureLog

  alias Jido.Debug
  alias Jido.Telemetry.Persistence

  defmodule InstanceSource do
    def __jido_persistence__, do: nil
  end

  defmodule AdapterSource do
    def get(_key, _opts), do: :not_found
  end

  @events for ending <- [:start, :stop, :exception],
              do: [:jido, :persistence, :operation, ending]

  @tag obligation: ["jido.telemetry.I2", "jido.telemetry.I3"]
  test "observes one persistence result with safe fields and revisions" do
    attach(self())

    source = {__MODULE__, secret: "adapter option"}

    assert :ok =
             Persistence.observe(
               :compare_and_swap,
               source,
               String,
               "agent-1",
               [
                 namespace: "tenant",
                 partition: "west",
                 reason: :commit,
                 expected_revision: 2,
                 revision: 3,
                 private: "secret"
               ],
               fn -> :ok end
             )

    assert_receive {:persistence_event, [:jido, :persistence, :operation, :start],
                    %{expected_revision: 2}, start_metadata}

    assert start_metadata == %{
             adapter_module: __MODULE__,
             agent_id: "agent-1",
             agent_module: String,
             agent_namespace: "tenant",
             agent_partition: "west",
             operation: :compare_and_swap,
             persistence_reason: :commit,
             schema_version: 1
           }

    assert_receive {:persistence_event, [:jido, :persistence, :operation, :stop],
                    %{duration: duration, revision_after: 3}, stop_metadata}

    assert duration >= 0
    assert stop_metadata.status == :ok
    refute inspect({start_metadata, stop_metadata}) =~ "secret"
  end

  @tag obligation: ["jido.telemetry.I3", "jido.telemetry.I8"]
  test "returns failures and re-raises faults after one terminal event" do
    attach(self())

    assert {:error, :conflict} =
             Persistence.observe(:load, nil, String, "agent-1", [], fn ->
               {:error, :conflict}
             end)

    assert_receive {:persistence_event, [:jido, :persistence, :operation, :start], _, _}

    assert_receive {:persistence_event, [:jido, :persistence, :operation, :stop], _,
                    %{status: :conflict}}

    assert_raise RuntimeError, "storage fault", fn ->
      Persistence.observe(:delete, nil, String, "agent-1", :invalid, fn ->
        raise "storage fault"
      end)
    end

    assert_receive {:persistence_event, [:jido, :persistence, :operation, :start], _, _}

    assert_receive {:persistence_event, [:jido, :persistence, :operation, :exception], _,
                    %{status: :error, kind: :error}}
  end

  @tag obligation: ["jido.telemetry.I2", "jido.telemetry.I3"]
  test "classifies load and default write revisions without result payloads" do
    attach(self())

    assert {:ok, :private_agent, 0} =
             Persistence.observe(:load, {__MODULE__, []}, String, "agent-1", [], fn ->
               {:ok, :private_agent, 0}
             end)

    assert_receive {:persistence_event, [:jido, :persistence, :operation, :start], %{}, _}

    assert_receive {:persistence_event, [:jido, :persistence, :operation, :stop],
                    %{duration: duration, revision_after: 0}, %{status: :ok}}

    assert duration >= 0

    assert :ok =
             Persistence.observe(
               :compare_and_swap,
               AdapterSource,
               String,
               "agent-1",
               [expected_revision: -1, revision: -1],
               fn -> :ok end
             )

    assert_receive {:persistence_event, [:jido, :persistence, :operation, :start], %{},
                    %{adapter_module: AdapterSource}}

    assert_receive {:persistence_event, [:jido, :persistence, :operation, :stop],
                    %{duration: second_duration}, %{status: :ok}}

    assert second_duration >= 0
  end

  @tag obligation: ["jido.telemetry.I3", "jido.telemetry.I4"]
  test "an inferred instance source applies only its own debug override" do
    Application.put_env(:jido, :telemetry, semantic_log_mode: :off)
    Debug.enable(InstanceSource, :on)

    on_exit(fn ->
      Debug.reset(InstanceSource)
      Application.delete_env(:jido, :telemetry)
    end)

    log =
      capture_log(fn ->
        assert {:error, :conflict} =
                 Persistence.observe(:load, InstanceSource, String, "agent-1", [], fn ->
                   {:error, :conflict}
                 end)
      end)

    assert log =~ "event=persistence.operation.stop"
    assert log =~ "status=conflict"
  end

  defp attach(owner) do
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach_many(
        handler,
        @events,
        fn event, measurements, metadata, owner ->
          send(owner, {:persistence_event, event, measurements, metadata})
        end,
        owner
      )

    on_exit(fn -> :telemetry.detach(handler) end)
  end
end
