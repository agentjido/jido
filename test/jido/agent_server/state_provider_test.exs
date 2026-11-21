defmodule Jido.AgentServer.StateProviderTest do
  use Covenant.Case, component: "jido.agent_server", async: false

  alias Jido.AgentServer

  defmodule Provider do
    @behaviour Jido.AgentServer.StateProvider

    @impl true
    def compile_state!(:count, _env) do
      {Jido.Joi.object(%{count: Jido.Joi.integer()}), :count}
    end

    @impl true
    def open(:count, _context, _mode, agent, open), do: open.(agent)

    @impl true
    def refresh(:count, _context, agent), do: {:ok, agent}

    @impl true
    def commit(:count, _context, _before, %{state: %{count: 3}}, _save),
      do: {:error, {:rejected, :not_allowed}}

    def commit(:count, _context, _before, candidate, save) do
      {:ok, canonical} = Jido.Agent.set(candidate, count: candidate.state.count * 2)
      save.(canonical)
    end
  end

  defmodule SetCount do
    use Jido.Action, name: "provider_set_count", schema: Jido.Joi.object(%{count: Jido.Joi.integer()})

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule Counter do
    use Jido.Agent, name: "provider_counter"
    import Jido.Agent.DSL.State, only: [state_provider: 2]

    state do
      state_provider(Provider, :count)
    end

    routes do
      route "count.set", SetCount
    end
  end

  @tag obligation: "jido.agent_server.I108"
  test "the provider commits canonical state and a rejected write leaves the agent usable" do
    start_supervised!(
      {Jido, name: Runtime, namespace: "test/state-provider", persistence: {Jido.Persistence.ETS, table: Store}}
    )

    {:ok, address} = Jido.agent_address(Runtime, "counter")
    assert {:ok, ^address} = Jido.create_agent(Runtime, address, Counter, state: %{count: 0})

    assert {:error, :state_provider_replacement_unsupported} =
             Jido.replace_agent(Runtime, address, Counter, expected: Jido.Agent.definition(Counter))

    assert {:ok, server} = Jido.activate_agent(Runtime, address)

    assert {:ok, %{status: :committed}} = AgentServer.call(server, signal(2))
    assert %{agent: %{state: %{count: 4}}} = AgentServer.snapshot(server)
    assert {:ok, %{state: %{count: 4}}, _, _, _} = Jido.Persistence.load_agent_address(Runtime, address)

    assert {:ok, %{status: :failed, error: :not_allowed}} = AgentServer.call(server, signal(3))
    assert %{agent: %{state: %{count: 4}}} = AgentServer.snapshot(server)
    assert {:ok, %{status: :committed}} = AgentServer.call(server, signal(4))
    assert %{agent: %{state: %{count: 8}}} = AgentServer.snapshot(server)
  end

  defp signal(count), do: Jido.Signal.new!("count.set", %{count: count}, source: "/counter")
end
