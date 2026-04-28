defmodule JidoTest.AgentServer.ClusterRuntimeTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer
  alias JidoTest.TestActions

  defmodule IncrementAction do
    @moduledoc false
    use Jido.Action,
      name: "cluster_increment",
      schema: [
        amount: [type: :integer, default: 1]
      ]

    @impl true
    def run(%{amount: amount}, context) do
      count = Map.get(context.state, :count, 0)
      {:ok, %{count: count + amount}}
    end
  end

  defmodule CounterAgent do
    @moduledoc false
    use Jido.Agent,
      name: "cluster_counter_agent",
      schema: [
        count: [type: :integer, default: 0]
      ],
      signal_routes: [
        {"inc", JidoTest.AgentServer.ClusterRuntimeTest.IncrementAction}
      ]
  end

  defmodule EffectsAgent do
    @moduledoc false
    use Jido.Agent,
      name: "cluster_effects_agent",
      schema: [
        triggered: [type: :boolean, default: false]
      ],
      signal_routes: [
        {"multi", TestActions.MultiEffectAction}
      ]
  end

  test "standby runtimes suppress directive side effects", context do
    pid =
      start_server(
        context,
        EffectsAgent,
        cluster_role: :standby,
        skip_schedules: true
      )

    signal = signal("multi")

    assert {:ok, agent} = AgentServer.call(pid, signal)
    assert agent.state.triggered == true

    assert {:ok, state} = AgentServer.state(pid)
    assert state.cluster_role == :standby
    assert :queue.is_empty(state.queue)
    assert state.cron_jobs == %{}
    assert state.children == %{}
  end

  test "cluster snapshot import and role promotion round-trip runtime state", context do
    primary = start_server(context, CounterAgent)
    signal = signal("inc", %{amount: 3})

    assert {:ok, updated} = AgentServer.call(primary, signal)
    assert updated.state.count == 3

    assert {:ok, snapshot} = AgentServer.cluster_snapshot(primary)

    standby =
      start_server(
        context,
        CounterAgent,
        cluster_role: :standby,
        skip_schedules: true
      )

    assert :ok = AgentServer.import_cluster_snapshot(standby, snapshot)

    assert {:ok, imported_state} = AgentServer.state(standby)
    assert imported_state.cluster_role == :standby
    assert imported_state.agent.state.count == 3

    assert :ok = AgentServer.promote(standby)
    assert {:ok, promoted_state} = AgentServer.state(standby)
    assert promoted_state.cluster_role == :primary

    assert :ok = AgentServer.demote(standby)
    assert {:ok, demoted_state} = AgentServer.state(standby)
    assert demoted_state.cluster_role == :standby
  end
end
