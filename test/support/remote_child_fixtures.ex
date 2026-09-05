defmodule JidoTest.RemoteChildFixtures.Apply do
  use Jido.Action, name: "test_remote_directive", schema: Zoi.object(%{directive: Zoi.any()})
  def run(%{directive: directive}, %{agent_state: state}), do: {:ok, state, [directive]}
end

defmodule JidoTest.RemoteChildFixtures.Hold do
  use Jido.Action, name: "test_remote_hold", schema: Zoi.object(%{observer: Zoi.any()})

  def run(%{observer: observer}, %{agent_state: state}) do
    task = self()
    Elixir.Agent.update(observer, fn _ -> task end)

    receive do
      :release -> {:ok, state}
    after
      10_000 -> {:error, :test_barrier_not_released}
    end
  end
end

defmodule JidoTest.RemoteChildFixtures.Parent do
  use Jido.Agent, name: "test_remote_parent"

  routes do
    route "test.remote.directive", JidoTest.RemoteChildFixtures.Apply
    route "jido.agent.child.*", Jido.Examples.KeepState
  end
end

defmodule JidoTest.RemoteChildFixtures.Child do
  use Jido.Agent, name: "test_remote_child"

  routes do
    route "test.remote.hold", JidoTest.RemoteChildFixtures.Hold
  end
end

defmodule JidoTest.RemoteChildFixtures do
  def start_parent(jido, opts) do
    policy = fn error, outcome ->
      Jido.RuntimeStore.put(jido, :remote_test_errors, outcome.agent_id, {error, outcome})
      :continue
    end

    Jido.start_agent(jido, __MODULE__.Parent, Keyword.put(opts, :error_policy, policy))
  end

  def observer do
    {:ok, pid} =
      Supervisor.start_child(Jido.Supervisor, %{
        id: make_ref(),
        start: {Elixir.Agent, :start_link, [fn -> nil end]}
      })

    pid
  end

  def observed(observer), do: Elixir.Agent.get(observer, &Function.identity/1)

  def inject_online_and_read_children(parent, message) do
    send(parent, message)
    Jido.AgentServer.children(parent)
  end
end
