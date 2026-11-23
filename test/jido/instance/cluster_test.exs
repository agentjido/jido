defmodule Jido.Instance.ClusterTest do
  use ExUnit.Case, async: true
  use Covenant.Case, component: "jido.instance", async: true

  alias Jido.Agent.Address
  alias Jido.Instance.{Cluster, Options}
  alias Jido.Persistence.ETS

  defmodule OfflineCluster do
    use Jido,
      otp_app: :jido,
      namespace: "test-offline-cluster",
      persistence: {Jido.Persistence.ETS, table: :test_cluster_offline}

    def config(_opts), do: [cluster: [home: :first@host, generation: "one"]]
  end

  @tag obligation: "jido.instance.I12"
  test "a stopped clustered module cannot select its compiled persistence directly" do
    assert {:error, :cluster_unavailable} =
             Jido.Persistence.resolve_source(OfflineCluster, instance: OfflineCluster)
  end

  @tag obligation: "jido.instance.I12"
  test "clustering is opt-in and validates the deployment configuration before storage" do
    assert {:ok, false} = Cluster.validate(false, nil, nil)
    refute Cluster.configured?(:invalid)
    assert Cluster.configured?(cluster: [home: :first@host])

    for options <- [
          nil,
          [],
          [home: nil],
          [home: :nonode@nohost],
          [home: :home@host, home: :other@host],
          [home: :home@host, extra: true],
          [home: :home@host, rpc_timeout: :infinity],
          [home: :home@host, generation: ""]
        ] do
      assert {:error, %Jido.Error.ValidationError{}} = Cluster.validate(options, "tickets", nil)
    end

    if not Node.alive?() do
      assert {:error, %Jido.Error.ValidationError{}} =
               Options.validate(name: __MODULE__, namespace: "tickets", cluster: [home: :home@host])
    end
  end

  @tag obligation: "jido.instance.I12"
  test "the durable home record uses exact CAS and can be confirmed independently" do
    id = System.unique_integer([:positive])
    profile = {ETS, table: :"jido_cluster_home_test_#{id}"}
    namespace = "cluster-test-#{id}"
    first = {:first@host, "first"}
    next = {:next@host, "next"}

    assert {:error, :cluster_home_not_provisioned} = Jido.check_cluster_home(profile, namespace, first)
    assert :ok = Jido.change_cluster_home(profile, namespace, :not_found, first)
    assert {:error, :conflict} = Jido.change_cluster_home(profile, namespace, :not_found, next)
    assert :ok = Jido.check_cluster_home(profile, namespace, first)
    assert {:error, :invalid_cluster_home} = Jido.change_cluster_home(profile, namespace, first, first)

    assert :ok = Jido.change_cluster_home(profile, namespace, first, next)
    assert {:error, :conflict} = Jido.change_cluster_home(profile, namespace, first, next)
    assert {:error, :cluster_home_mismatch} = Jido.check_cluster_home(profile, namespace, first)
    assert :ok = Jido.check_cluster_home(profile, namespace, next)
  end

  @tag obligation: "jido.instance.I12"
  test "the RPC entry rejects unknown protocols and never falls back to a local instance" do
    namespace = "cluster-protocol-#{System.unique_integer([:positive])}"
    instance = __MODULE__.Local
    start_supervised!({Jido, name: instance, namespace: namespace})
    address = Address.new!(namespace: namespace, id: "agent")

    for protocol <- [:invalid, :jido_cluster_v1] do
      assert {:jido_cluster_v1, {:error, :cluster_unavailable}} =
               Jido.__cluster_dispatch__(protocol, instance, node(), "old", address, :status, [100])
    end
  end
end
