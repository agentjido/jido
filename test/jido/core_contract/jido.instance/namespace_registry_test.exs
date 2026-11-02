Code.require_file("support.ex", __DIR__)

defmodule JidoTest.InstanceNamespaceRegistryTest do
  use ExUnit.Case, async: false
  use Covenant.Case, component: "jido.instance", async: false

  import JidoTest.Eventually

  alias Jido.Instance.NamespaceRegistry

  setup :ensure_namespace_registry

  defp ensure_namespace_registry(context),
    do: JidoTest.InstanceContractSupport.ensure_namespace_registry(context)

  @tag obligation: "jido.instance.I3"
  test "claims are exact, idempotent for one instance, and releasable" do
    namespace = unique_namespace("claim")
    instance = unique_instance("claim")
    other = unique_instance("other")

    assert {:ok, claim} = NamespaceRegistry.claim(namespace, instance)
    assert is_reference(claim)
    assert NamespaceRegistry.lookup(namespace) == {instance, self()}
    assert NamespaceRegistry.namespace(instance) == namespace
    assert {:ok, :existing} = NamespaceRegistry.claim(namespace, instance)
    assert :ok = NamespaceRegistry.bind(:existing, namespace, instance, self())

    assert {:error, error} = NamespaceRegistry.claim(namespace, other)
    assert Jido.Error.code(error) == :jido_namespace_already_bound
    assert error.details.namespace == namespace
    assert error.details.owner == self()

    assert :ok = NamespaceRegistry.release(claim)
    assert :ok = NamespaceRegistry.release(claim)
    assert NamespaceRegistry.lookup(namespace) == nil
    assert :ok = NamespaceRegistry.release(nil)
    assert :ok = NamespaceRegistry.release(:existing)
  end

  @tag obligation: "jido.instance.I3"
  test "binding requires the matching claim and follows the bound owner" do
    namespace = unique_namespace("bind")
    instance = unique_instance("bind")
    owner = spawn(fn -> Process.sleep(:infinity) end)
    on_exit(fn -> if Process.alive?(owner), do: Process.exit(owner, :kill) end)

    assert {:ok, claim} = NamespaceRegistry.claim(namespace, instance)

    assert {:error, wrong_instance} =
             NamespaceRegistry.bind(claim, namespace, unique_instance("wrong"), owner)

    assert Jido.Error.code(wrong_instance) == :jido_namespace_already_bound
    assert {:error, wrong_claim} = NamespaceRegistry.bind(make_ref(), namespace, instance, owner)
    assert Jido.Error.code(wrong_claim) == :jido_namespace_already_bound

    assert {:error, missing_claim} =
             NamespaceRegistry.bind(make_ref(), unique_namespace("missing"), instance, owner)

    assert Jido.Error.code(missing_claim) == :jido_namespace_already_bound
    assert :ok = NamespaceRegistry.bind(claim, namespace, instance, owner)
    assert NamespaceRegistry.lookup(namespace) == {instance, owner}

    Process.exit(owner, :kill)
    assert_eventually(NamespaceRegistry.lookup(namespace) == nil)
  end

  @tag obligation: "jido.instance.I3"
  test "an existing claim can bind after the previous binding is gone" do
    namespace = unique_namespace("existing")
    instance = unique_instance("existing")
    owner = spawn(fn -> Process.sleep(:infinity) end)
    on_exit(fn -> if Process.alive?(owner), do: Process.exit(owner, :kill) end)

    assert :ok = NamespaceRegistry.bind(:existing, namespace, instance, owner)
    assert :ok = NamespaceRegistry.bind(:existing, namespace, instance, owner)
    assert NamespaceRegistry.lookup(namespace) == {instance, owner}

    assert {:error, error} =
             NamespaceRegistry.bind(:existing, namespace, unique_instance("wrong"), owner)

    assert Jido.Error.code(error) == :jido_namespace_already_bound
    assert error.details.owner == owner

    assert {:error, owner_error} =
             NamespaceRegistry.bind(:existing, namespace, instance, self())

    assert Jido.Error.code(owner_error) == :jido_namespace_already_bound
    assert owner_error.details.owner == owner

    Process.exit(owner, :kill)
    assert_eventually(NamespaceRegistry.lookup(namespace) == nil)
  end

  @tag obligation: "jido.instance.I3"
  test "rebinding and release remove obsolete owner monitors" do
    registry = Process.whereis(NamespaceRegistry)
    namespace = unique_namespace("monitor-rebind")
    instance = unique_instance("monitor-rebind")
    parent = self()

    claimant =
      spawn(fn ->
        {:ok, claim} = NamespaceRegistry.claim(namespace, instance)
        send(parent, {:claim, claim})
        receive do: (:stop -> :ok)
      end)

    owner = spawn(fn -> Process.sleep(:infinity) end)

    on_exit(fn ->
      for pid <- [claimant, owner], Process.alive?(pid), do: Process.exit(pid, :kill)
    end)

    assert_receive {:claim, claim}
    assert {:monitors, monitors} = Process.info(registry, :monitors)
    assert {:process, claimant} in monitors

    assert :ok = NamespaceRegistry.bind(claim, namespace, instance, owner)
    assert {:monitors, monitors} = Process.info(registry, :monitors)
    refute {:process, claimant} in monitors
    assert {:process, owner} in monitors

    send(claimant, :stop)
    assert_eventually(NamespaceRegistry.lookup(namespace) == {instance, owner})

    assert :ok = NamespaceRegistry.release(claim)
    assert {:monitors, monitors} = Process.info(registry, :monitors)
    refute {:process, owner} in monitors
    assert NamespaceRegistry.lookup(namespace) == nil
  end

  @tag obligation: "jido.instance.I3"
  test "restart restores live bindings and removes stale or released bindings" do
    live_namespace = unique_namespace("restart-live")
    stale_namespace = unique_namespace("restart-stale")
    released_namespace = unique_namespace("restart-released")
    claimed_namespace = unique_namespace("restart-claimed")
    live_instance = unique_instance("restart-live")
    stale_instance = unique_instance("restart-stale")
    released_instance = unique_instance("restart-released")
    claimed_instance = unique_instance("restart-claimed")
    live_owner = spawn(fn -> Process.sleep(:infinity) end)
    stale_owner = spawn(fn -> Process.sleep(:infinity) end)

    on_exit(fn ->
      for pid <- [live_owner, stale_owner], Process.alive?(pid), do: Process.exit(pid, :kill)
    end)

    assert :ok = NamespaceRegistry.bind(:existing, live_namespace, live_instance, live_owner)
    assert :ok = NamespaceRegistry.bind(:existing, stale_namespace, stale_instance, stale_owner)
    assert {:ok, released_claim} = NamespaceRegistry.claim(released_namespace, released_instance)
    assert :ok = NamespaceRegistry.release(released_claim)
    assert {:ok, claimed_token} = NamespaceRegistry.claim(claimed_namespace, claimed_instance)

    assert :ok = Supervisor.terminate_child(Jido.Supervisor, NamespaceRegistry)
    Process.exit(stale_owner, :kill)
    assert {:ok, _registry} = Supervisor.restart_child(Jido.Supervisor, NamespaceRegistry)

    assert NamespaceRegistry.lookup(live_namespace) == {live_instance, live_owner}
    assert NamespaceRegistry.lookup(stale_namespace) == nil
    assert NamespaceRegistry.lookup(released_namespace) == nil
    assert NamespaceRegistry.lookup(claimed_namespace) == {claimed_instance, self()}
    assert :ets.lookup(Jido.Instance.NamespaceRegistry.Table, stale_namespace) == []

    assert :ok = NamespaceRegistry.release(claimed_token)
    assert NamespaceRegistry.lookup(claimed_namespace) == nil

    Process.exit(live_owner, :kill)
    assert_eventually(NamespaceRegistry.lookup(live_namespace) == nil)
  end

  @tag obligation: "jido.instance.I3"
  test "an unrelated process monitor message does not stop the registry" do
    registry = Process.whereis(NamespaceRegistry)
    send(registry, {:DOWN, make_ref(), :process, self(), :normal})
    assert NamespaceRegistry.lookup(unique_namespace("unknown-monitor")) == nil
    assert Process.alive?(registry)
  end

  defp unique_instance(label) do
    String.to_atom("jido_namespace_registry_#{label}_#{System.unique_integer([:positive])}")
  end

  defp unique_namespace(label) do
    "jido/test/namespace-registry/#{label}/#{System.unique_integer([:positive])}"
  end
end
