defmodule Jido.Telemetry.PersistenceTest do
  use Covenant.Case, component: "jido.telemetry", async: false

  import ExUnit.CaptureLog

  alias Jido.Telemetry
  alias Jido.Telemetry.Persistence
  alias Jido.Test.AgentServer.RuntimeFixtures.RuntimeAgent

  defmodule InstanceSource do
    def __jido_persistence__, do: nil
  end

  defmodule UpgradeAction do
    use Jido.Action, name: "telemetry_reason_upgrade"
    def run(%{snapshot: snapshot}, _context), do: {:ok, %{snapshot: snapshot}}
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

    assert_receive {:persistence_event, [:jido, :persistence, :operation, :start], %{expected_revision: 2},
                    start_metadata}

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

    assert_receive {:persistence_event, [:jido, :persistence, :operation, :stop], _, %{status: :conflict}}

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

    assert_receive {:persistence_event, [:jido, :persistence, :operation, :stop], second_measurements, %{status: :ok}}

    assert %{duration: second_duration} = second_measurements
    assert second_duration >= 0
    refute Map.has_key?(second_measurements, :revision_after)

    assert :ok =
             Persistence.observe(
               :compare_and_swap,
               AdapterSource,
               String,
               "agent-1",
               [expected_revision: 0],
               fn -> :ok end
             )

    assert_receive {:persistence_event, [:jido, :persistence, :operation, :start], %{expected_revision: 0}, _}

    assert_receive {:persistence_event, [:jido, :persistence, :operation, :stop],
                    %{duration: third_duration, revision_after: 0}, %{status: :ok}}

    assert third_duration >= 0
  end

  @tag obligation: ["jido.telemetry.I3", "jido.telemetry.I4"]
  test "an inferred instance source applies only its own debug override" do
    Application.put_env(:jido, :telemetry, semantic_log_mode: :off)
    Telemetry.set_debug(InstanceSource, :on)

    on_exit(fn ->
      Telemetry.set_debug(InstanceSource, :off)
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

  @tag obligation: ["jido.telemetry.I2", "jido.telemetry.I3", "jido.telemetry.I4"]
  test "a live instance source supplies its namespace and debug scope" do
    attach(self())
    suffix = System.unique_integer([:positive])
    instance = :"telemetry_live_instance_#{suffix}"
    namespace = "telemetry/live/#{suffix}"
    start_supervised!({Jido, name: instance, namespace: namespace})

    Application.put_env(:jido, :telemetry, semantic_log_mode: :off)
    Telemetry.set_debug(instance, :on)

    on_exit(fn ->
      Telemetry.set_debug(instance, :off)
      Application.delete_env(:jido, :telemetry)
    end)

    log =
      capture_log(fn ->
        assert {:error, :conflict} =
                 Persistence.observe(:load, instance, String, "agent-1", [], fn ->
                   {:error, :conflict}
                 end)
      end)

    assert_receive {:persistence_event, [:jido, :persistence, :operation, :start], _, %{agent_namespace: ^namespace}}

    assert_receive {:persistence_event, [:jido, :persistence, :operation, :stop], _, %{status: :conflict}}

    assert log =~ "event=persistence.operation.stop"
  end

  @tag obligation: ["jido.telemetry.I3", "jido.telemetry.I4"]
  test "a partial process pair is not an instance debug scope" do
    source = :"telemetry_partial_instance_#{System.unique_integer([:positive])}"
    pid = spawn(fn -> receive do: (:stop -> :ok) end)
    Process.register(pid, source)
    Application.put_env(:jido, :telemetry, semantic_log_mode: :off)
    Telemetry.set_debug(source, :on)

    on_exit(fn ->
      Telemetry.set_debug(source, :off)
      Application.delete_env(:jido, :telemetry)
      send(pid, :stop)
    end)

    log =
      capture_log(fn ->
        assert {:error, :conflict} =
                 Persistence.observe(:load, source, String, "agent-1", [], fn ->
                   {:error, :conflict}
                 end)
      end)

    assert log == ""
  end

  @tag obligation: "jido.telemetry.I3"
  test "persistence observation rejects unsupported calls before work runs" do
    refute_received :ran

    assert_raise FunctionClauseError, fn ->
      apply(Persistence, :observe, [
        :invalid,
        nil,
        String,
        "agent-1",
        [],
        fn -> send(self(), :ran) end
      ])
    end

    assert_raise FunctionClauseError, fn ->
      apply(Persistence, :observe, [:load, nil, String, "agent-1", [], :not_a_function])
    end

    refute_received :ran
  end

  describe "persistence reasons from real writers" do
    setup do
      table = :"telemetry_reason_#{System.unique_integer([:positive])}"
      instance = :"telemetry_reason_instance_#{System.unique_integer([:positive])}"

      start_supervised!(
        {Jido, name: instance, namespace: "tests/#{instance}", persistence: {Jido.Persistence.ETS, table: table}}
      )

      attach(self())
      %{instance: instance}
    end

    @tag obligation: ["jido.telemetry.I2", "jido.telemetry.I3"]
    test "create, commit, hibernate, and upgrade writes report distinct reasons", c do
      id = "reasons-#{System.unique_integer([:positive])}"

      {:ok, pid} = Jido.start_agent(c.instance, RuntimeAgent, id: id, persistence: :inherit)
      :ok = Jido.AgentServer.await_ready(pid)
      assert write_reason(id) == :activate

      {:ok, _, _} =
        Jido.AgentServer.call(pid, Jido.Signal.new!("runtime.record", %{event: :saved}, source: "/test"))

      assert write_reason(id) == :commit

      :ok = Jido.AgentServer.hibernate(pid)
      assert write_reason(id) == :hibernate

      assert {:ok, _upgraded, _revision} =
               Jido.Persistence.upgrade_agent(c.instance, RuntimeAgent, id, UpgradeAction, instance: c.instance)

      assert write_reason(id) == :stored_upgrade
    end
  end

  @tag obligation: ["jido.telemetry.I2", "jido.telemetry.I3"]
  test "every load function reports revision_after" do
    attach(self())
    store = {Jido.Persistence.ETS, table: :"telemetry_load_#{System.unique_integer([:positive])}"}
    opts = [namespace: "tests/telemetry-load"]
    agent = RuntimeAgent.instantiate!(id: "loaded-#{System.unique_integer([:positive])}")
    :ok = Jido.Persistence.save_agent(store, agent, opts ++ [revision: 4])

    for load <- [
          &Jido.Persistence.load_agent/4,
          &Jido.Persistence.load_agent_with_revision/4,
          &Jido.Persistence.load_agent_with_server_turn/4
        ] do
      assert :ok == load.(store, RuntimeAgent, agent.id, opts) |> elem(0)

      assert_receive {:persistence_event, [:jido, :persistence, :operation, :stop], %{revision_after: 4},
                      %{operation: :load, status: :ok}}
    end
  end

  defp write_reason(id) do
    receive do
      {:persistence_event, [:jido, :persistence, :operation, :stop], _measurements,
       %{operation: :compare_and_swap, agent_id: ^id} = metadata} ->
        metadata[:persistence_reason]
    after
      2_000 -> flunk("no write event for #{id}")
    end
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
