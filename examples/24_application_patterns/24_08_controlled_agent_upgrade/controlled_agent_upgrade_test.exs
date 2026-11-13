Code.require_file("controlled_agent_upgrade.ex", __DIR__)

defmodule Jido.Examples.Patterns.ControlledUpgradeTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.AgentServer

  alias Jido.Examples.Patterns.ControlledUpgrade.{
    AccountV1,
    AccountV2,
    FailUpgrade,
    RollbackToV1Shape,
    ToV2
  }

  test "quiesce, migrate, replace, fail safely, and roll back under one Agent Ref" do
    {jido, ref} = start_account()
    {:ok, first} = Jido.activate_agent(jido, ref)

    assert {:ok, %AgentServer.TurnResult{status: :committed}} =
             Jido.call(jido, ref, AccountV1.increment_signal!(%{}))

    assert AgentServer.snapshot(first).agent.state == %{count: 3}
    assert {:ok, %{admission: :quiesced}} = AgentServer.quiesce(first)

    assert {:error, :quiesced} =
             AgentServer.call(first, AccountV1.increment_signal!(%{}))

    assert {:ok, ^ref} = Jido.upgrade_agent(jido, ref, ToV2)
    {:ok, second} = Jido.activate_agent(jido, ref)
    refute second == first

    assert %{module: AccountV1, vsn: 2, state: %{total: 3, currency: "USD"}} =
             AgentServer.snapshot(second).agent

    assert {:ok, %AgentServer.TurnResult{status: :committed}} =
             Jido.call(jido, ref, AccountV2.increment_signal!(%{}))

    assert AgentServer.snapshot(second).agent.state.total == 4
    assert {:ok, %{admission: :quiesced}} = AgentServer.quiesce(second)

    assert {:error, %Jido.Error.ExecutionError{message: "injected migration failure"}} =
             Jido.upgrade_agent(jido, ref, FailUpgrade)

    {:ok, after_failure} = Jido.activate_agent(jido, ref)

    assert %{module: AccountV1, vsn: 2, state: %{total: 4, currency: "USD"}} =
             AgentServer.snapshot(after_failure).agent

    assert {:ok, ^ref} = Jido.upgrade_agent(jido, ref, RollbackToV1Shape)
    {:ok, rolled_back} = Jido.activate_agent(jido, ref)

    assert %{module: AccountV1, vsn: 3, state: %{count: 4}} =
             AgentServer.snapshot(rolled_back).agent

    assert AgentServer.snapshot(rolled_back).agent_ref == ref
  end

  defp start_account do
    suffix = System.unique_integer([:positive])
    namespace = "examples/controlled-upgrade/#{suffix}"
    jido = :"controlled_upgrade_#{suffix}"
    persistence = {Jido.Persistence.ETS, table: Module.concat(__MODULE__, "Store#{suffix}")}

    start_supervised!(
      {Jido, name: jido, namespace: namespace, persistence: persistence},
      id: jido
    )

    {:ok, ref} = Jido.agent_ref(jido, "upgrade-account")
    agent = AccountV1.instantiate!(id: ref.id, state: %{count: 2})
    {:ok, ^ref} = Jido.create_agent(jido, ref, agent)
    {jido, ref}
  end
end
