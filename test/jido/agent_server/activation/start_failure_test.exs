defmodule Jido.AgentServer.ActivationStartFailureTest do
  use Jido.Test.Case, async: false
  use Covenant.Case, component: "jido.agent_server.activation", async: false

  alias Jido.AgentServer, as: Server

  @moduletag capture_log: true

  defmodule Worker do
    use Jido.Agent, name: "start_failure_worker"
  end

  setup do
    table = :"start_failure_#{System.unique_integer([:positive])}"
    instance = :"start_failure_instance_#{System.unique_integer([:positive])}"

    start_supervised!(
      {Jido, name: instance, namespace: "tests/#{instance}", persistence: {Jido.Persistence.ETS, table: table}}
    )

    %{instance: instance}
  end

  defp result({:ok, pid}), do: Server.await_ready(pid, 2_000)
  defp result(other), do: other

  @tag obligation: "jido.agent_server.activation.I4"
  test "a failed thaw reports not_found in every run of the race", c do
    results =
      for i <- 1..200, do: result(Jido.thaw(c.instance, Worker, "missing-#{i}"))

    assert Enum.uniq(results) == [{:error, :not_found}]
  end

  @tag obligation: "jido.agent_server.activation.I4"
  test "a strict start over a save reports conflict in every run of the race", c do
    results =
      for i <- 1..50 do
        id = "saved-#{i}"
        {:ok, first} = Jido.start_agent(c.instance, Worker, id: id, persistence: :inherit)
        :ok = Server.await_ready(first)
        :ok = Server.stop(first)
        result(Jido.start_agent(c.instance, Worker, id: id, persistence: :inherit))
      end

    assert Enum.uniq(results) == [{:error, :conflict}]
  end

  @tag obligation: "jido.agent_server.activation.I4"
  test "a start over a tombstone reports deleted in every run of the race", c do
    results =
      for i <- 1..50 do
        {:ok, ref} = Jido.agent_ref(c.instance, "gone-#{i}")
        :ok = Jido.delete_agent(c.instance, ref, Worker)
        result(Jido.activate_agent(c.instance, ref, Worker))
      end

    assert Enum.uniq(results) == [{:error, :deleted}]
  end

  @tag obligation: "jido.agent_server.activation.I4"
  test "await_ready returns the reason after the failed worker has exited", c do
    pid = failed_worker(c.instance)

    assert Server.await_ready(pid) == {:error, :not_found}
  end

  @tag obligation: "jido.agent_server.activation.I4"
  test "await_ready returns noproc for a process with no recorded failure" do
    pid = spawn(fn -> :ok end)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}

    assert Server.await_ready(pid) == {:error, :noproc}
    assert Server.await_ready(:start_failure_unregistered_name) == {:error, :noproc}
  end

  @tag obligation: "jido.agent_server.activation.I4"
  test "await_ready returns a timeout error", c do
    {:ok, pid} = Jido.start_agent(c.instance, Worker, id: "slow")
    :ok = :sys.suspend(pid)

    try do
      assert Server.await_ready(pid, 0) == {:error, :timeout}
    after
      :sys.resume(pid)
    end
  end

  describe "listing on an instance that is not running" do
    @tag obligation: "jido.agent_server.activation.I2"
    test "list_agents and agent_count return an error for a stopped instance" do
      instance = :"start_failure_stopped_#{System.unique_integer([:positive])}"
      {:ok, _} = Jido.start(name: instance)
      :ok = Jido.stop(instance)

      assert {:error, %Jido.Error.ValidationError{}} = Jido.list_agents(instance)
      assert {:error, %Jido.Error.ValidationError{}} = Jido.agent_count(instance)
    end

    @tag obligation: "jido.agent_server.activation.I2"
    test "list_agents and agent_count return an error for a never-started instance" do
      instance = :"start_failure_never_#{System.unique_integer([:positive])}"

      assert {:error, %Jido.Error.ValidationError{}} = Jido.list_agents(instance)
      assert {:error, %Jido.Error.ValidationError{}} = Jido.agent_count(instance)
    end

    @tag obligation: "jido.agent_server.activation.I2"
    test "list_agents and agent_count still report a running instance", c do
      assert Jido.list_agents(c.instance) == []
      assert Jido.agent_count(c.instance) == 0
    end
  end

  describe "hibernate with a partition" do
    @tag obligation: "jido.agent_server.activation.I2"
    test "a matching partition hibernates and a wrong partition is not found", c do
      {:ok, pid} =
        Jido.start_agent(c.instance, Worker, id: "partitioned", partition: "east", persistence: :inherit)

      :ok = Server.await_ready(pid)

      assert Jido.hibernate(c.instance, pid, partition: "west") == {:error, :not_found}
      assert Process.alive?(pid)

      assert Jido.hibernate(c.instance, pid, partition: "east", timeout: 2_000) == :ok
      refute Process.alive?(pid)
    end
  end

  describe "persistence without a namespace" do
    setup do
      instance = :"start_failure_plain_#{System.unique_integer([:positive])}"
      store = {Jido.Persistence.ETS, table: :"#{instance}_store"}
      start_supervised!({Jido, name: instance, persistence: store})
      %{plain: instance, store: store}
    end

    @tag obligation: "jido.agent_server.activation.I2"
    test "every start returns an error and starts no worker", c do
      starts = [
        fn -> Jido.start_agent(c.plain, Worker, id: "a", persistence: :inherit) end,
        fn -> Jido.start_agent(c.plain, Worker, id: "a", persistence: c.store) end,
        fn -> Jido.thaw(c.plain, Worker, "a") end
      ]

      for start <- starts do
        assert {:error, %Jido.Error.ValidationError{message: message}} = start.()
        assert message =~ "stable namespace"
        assert Jido.Instance.Names.agent_supervisor(c.plain) |> DynamicSupervisor.which_children() == []
      end
    end

    @tag obligation: "jido.agent_server.activation.I2"
    test "an instance default is checked when the Agent starts", c do
      instance = :"start_failure_default_#{System.unique_integer([:positive])}"
      start_supervised!({Jido, name: instance, persistence: c.store, agent_server: [persistence: :inherit]})

      assert {:error, %Jido.Error.ValidationError{}} = Jido.start_agent(instance, Worker, id: "a")
      assert Jido.Instance.Names.agent_supervisor(instance) |> DynamicSupervisor.which_children() == []
    end

    @tag obligation: "jido.agent_server.activation.I2"
    test "a start with no persistence still succeeds", c do
      assert {:ok, pid} = Jido.start_agent(c.plain, Worker, id: "plain")
      assert Server.await_ready(pid) == :ok
    end
  end

  defp failed_worker(instance, attempt \\ 0) do
    case Jido.thaw(instance, Worker, "missing-worker-#{attempt}") do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 2_000
        pid

      {:error, :not_found} when attempt < 200 ->
        failed_worker(instance, attempt + 1)
    end
  end
end
