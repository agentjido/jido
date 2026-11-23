defmodule Jido.Instance.ClusterPeerTest do
  use Jido.Test.AgentServer.PeerCase, async: false

  alias Jido.Instance.Names
  alias Jido.Test.AgentServer.RuntimeFixtures.RuntimeAgent

  test "ingress fetches state at the home without activating a passivated Agent", c do
    {instance, address, worker, signal} = start_home(c)

    opts = [
      name: instance,
      namespace: address.namespace,
      cluster: [home: c.node_a, generation: "generation"]
    ]

    assert {:ok, _pid} = peer_call(c.peer_b, Supervisor, :start_child, [Jido.Supervisor, {Jido, opts}])

    assert {:ok, %{ticks: 0}} = peer_call(c.peer_b, Jido, :fetch_state, [instance, address])
    assert {:ok, %{status: :committed}} = peer_call(c.peer_a, Jido.AgentServer, :call, [worker, signal])
    assert {:ok, %Jido.AgentServer.Snapshot{}} = peer_call(c.peer_a, Jido.AgentServer, :stop, [worker])

    assert {:ok, %{ticks: 1}} = peer_call(c.peer_b, Jido, :fetch_state, [instance, address])
    assert %{residency: :passivated} = peer_call(c.peer_a, Jido, :status, [instance, address])
  end

  test "a cached Worker refuses admission while an instance dependency is down", c do
    {instance, address, worker, signal} = start_home(c)

    assert :ok = peer_call(c.peer_a, Supervisor, :terminate_child, [instance, Names.runtime_store(instance)])
    assert {:error, :cluster_unavailable} = peer_call(c.peer_a, Jido.AgentServer, :call, [worker, signal])
    assert {:error, :cluster_unavailable} = peer_call(c.peer_a, Jido, :call, [instance, address, signal])
    assert %{agent_revision: 0} = peer_call(c.peer_a, Jido.AgentServer, :status, [worker])
  end

  test "direct lifecycle calls refuse work while Wake is unavailable", c do
    {instance, address, _worker, _signal} = start_home(c)
    assert :ok = peer_call(c.peer_a, Supervisor, :terminate_child, [instance, Jido.Instance.Wake])

    assert {:error, :cluster_unavailable} = peer_call(c.peer_a, Jido, :activate_agent, [instance, address])

    new_address = %{address | id: "not-created"}

    assert {:error, :cluster_unavailable} =
             peer_call(c.peer_a, Jido, :create_agent, [instance, new_address, RuntimeAgent])
  end

  test "missing cluster role data cannot admit work as a local instance", c do
    {instance, address, worker, signal} = start_home(c)

    assert :ok =
             peer_call(c.peer_a, Jido.Instance.RuntimeStore, :delete, [instance, :jido_instance_config, :cluster])

    assert {:error, :cluster_unavailable} = peer_call(c.peer_a, Jido, :call, [instance, address, signal])
    assert {:error, :cluster_unavailable} = peer_call(c.peer_a, Jido.AgentServer, :call, [worker, signal])
    assert {:error, :cluster_unavailable} = peer_call(c.peer_a, Jido.Persistence, :resolve_config, [:inherit, instance])
    assert %{agent_revision: 0} = peer_call(c.peer_a, Jido.AgentServer, :status, [worker])
  end

  test "a queued Turn cannot use a replacement Runner", c do
    {instance, _address, worker, signal} = start_home(c)
    runner = peer_call(c.peer_a, Process, :whereis, [Names.exec_runner(instance)])
    children = peer_call(c.peer_a, Supervisor, :which_children, [instance])
    assert {runner_id, ^runner, _, _} = List.keyfind(children, runner, 1)
    assert :ok = peer_call(c.peer_a, :sys, :suspend, [worker])

    request = Task.async(fn -> peer_call(c.peer_a, Jido.AgentServer, :call, [worker, signal]) end)

    peer_eventually(fn ->
      {:messages, messages} = peer_call(c.peer_a, Process, :info, [worker, :messages])
      Enum.any?(messages, &match?({:"$gen_call", _, {:turn, _, _, _, _, _}}, &1))
    end)

    assert :ok = peer_call(c.peer_a, Supervisor, :terminate_child, [instance, runner_id])
    assert {:ok, replacement} = peer_call(c.peer_a, Supervisor, :restart_child, [instance, runner_id])
    refute replacement == runner

    assert :ok = peer_call(c.peer_a, :sys, :resume, [worker])
    assert {:error, :cluster_unavailable} = Task.await(request)
  end

  test "a short home call expires before dispatch when resolution stalls", c do
    {instance, address, worker, signal} = start_home(c)
    store = Names.runtime_store(instance)
    assert :ok = peer_call(c.peer_a, :sys, :suspend, [store])

    try do
      assert {:error, :cluster_unavailable} =
               peer_call(c.peer_a, Jido, :call, [instance, address, signal, [timeout: 50]], 1_000)

      assert {:error, :admission_timeout} =
               peer_call(c.peer_a, Jido, :call, [instance, address, signal, [admission_timeout: 50]], 1_000)
    after
      assert :ok = peer_call(c.peer_a, :sys, :resume, [store])
    end

    assert %{agent_revision: 0} = peer_call(c.peer_a, Jido.AgentServer, :status, [worker])
  end

  test "namespace lookup stays inside the home call budget", c do
    {instance, address, worker, signal} = start_home(c)
    registry = Jido.Instance.NamespaceRegistry
    assert :ok = peer_call(c.peer_a, :sys, :suspend, [registry])

    try do
      assert {:error, :cluster_unavailable} =
               peer_call(c.peer_a, Jido, :call, [instance, address, signal, [timeout: 50]], 1_000)
    after
      assert :ok = peer_call(c.peer_a, :sys, :resume, [registry])
    end

    assert %{agent_revision: 0} = peer_call(c.peer_a, Jido.AgentServer, :status, [worker])
  end

  test "generic startup rejects a generated instance with a compiled Store", c do
    instance = Jido.Test.Persistence.CLIInstance

    opts = [
      name: instance,
      namespace: "cluster-compiled-store",
      persistence: {Jido.Persistence.ETS, table: __MODULE__},
      cluster: [home: c.node_a, generation: "generation"]
    ]

    assert {:error, %Jido.Error.ValidationError{message: message}} =
             peer_call(c.peer_a, Jido, :start_link, [opts])

    assert message =~ "require runtime persistence"
  end

  defp start_home(c) do
    instance = __MODULE__.Home
    namespace = "cluster-peer-readiness"
    profile = {Jido.Persistence.ETS, table: __MODULE__}
    home = {c.node_a, "generation"}

    assert :ok = peer_call(c.peer_a, Jido, :change_cluster_home, [profile, namespace, :not_found, home])

    opts = [
      name: instance,
      namespace: namespace,
      persistence: profile,
      cluster: [home: c.node_a, generation: "generation"]
    ]

    assert {:ok, _pid} = peer_call(c.peer_a, Supervisor, :start_child, [Jido.Supervisor, {Jido, opts}])
    assert {:ok, address} = peer_call(c.peer_a, Jido, :agent_address, [instance, "worker"])
    assert {:ok, ^address} = peer_call(c.peer_a, Jido, :create_agent, [instance, address, RuntimeAgent])
    assert {:ok, worker} = peer_call(c.peer_a, Jido, :activate_agent, [instance, address])

    {instance, address, worker, Jido.Signal.new!("cron.tick", %{}, source: "/test/cluster")}
  end
end
