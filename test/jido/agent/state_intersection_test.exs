defmodule Jido.Agent.StateIntersectionTest do
  use JidoTest.Case, async: true

  alias Jido.Agent
  alias Jido.AgentServer

  def observe(value, label, _opts) do
    send(self(), {:intersection_checked, label, value})
    :ok
  end

  def schema(reverse? \\ false) do
    branches = [
      Zoi.object(%{
        a: Zoi.integer() |> Zoi.refine({__MODULE__, :observe, [:a]}) |> Zoi.default(1)
      }),
      Zoi.object(%{
        b: Zoi.integer() |> Zoi.refine({__MODULE__, :observe, [:b]}) |> Zoi.default(2)
      })
    ]

    branches = if reverse?, do: Enum.reverse(branches), else: branches
    Zoi.object(%{nested: Zoi.intersection(branches)})
  end

  test "creation retains both intersection fields and checks each branch once" do
    for reverse? <- [false, true], nested <- [%{a: 3, b: 4}, %{}] do
      definition = Agent.new!(name: "intersection_state", schema: schema(reverse?))
      assert {:ok, agent} = Agent.instantiate(definition, state: %{nested: nested})
      expected = Map.merge(%{a: 1, b: 2}, nested)
      assert agent.state === %{nested: expected}
      assert_received {:intersection_checked, :a, a}
      assert_received {:intersection_checked, :b, b}
      assert a === expected.a
      assert b === expected.b
      refute_received {:intersection_checked, _, _}
      assert Agent.validate_instance(agent) === {:ok, agent}
      assert_received {:intersection_checked, :a, ^a}
      assert_received {:intersection_checked, :b, ^b}
      refute_received {:intersection_checked, _, _}
    end
  end

  test "updates and checkpoint restore retain stored values and reject missing fields" do
    definition = Agent.new!(name: "intersection_restore", schema: schema())
    agent = Agent.instantiate!(definition, state: %{nested: %{a: 3, b: 4}})
    candidate = %{nested: %{a: 5, b: 6}}
    assert {:ok, updated} = Agent.transition(agent, candidate)
    assert updated.state === candidate
    assert {:ok, checkpoint} = Agent.checkpoint(updated)
    assert Agent.restore(Agent, checkpoint) === {:ok, updated}

    for invalid <- [%{nested: %{a: 5}}, %{nested: %{b: 6}}, %{nested: %{a: nil, b: 6}}] do
      assert {:error, %Jido.Error.ValidationError{}} = Agent.transition(updated, invalid)

      assert {:error, %Jido.Error.ValidationError{}} =
               Agent.restore(Agent, %{checkpoint | state: invalid})

      assert updated.state === candidate
    end
  end

  defmodule Keep do
    use Jido.Action, name: "intersection_keep"
    def run(_params, context), do: {:ok, context.agent_state}
  end

  defmodule Owned do
    use Jido.Plugin

    @impl true
    def state_spec(_opts) do
      {:owned,
       Zoi.object(%{
         nested:
           Zoi.intersection([
             Zoi.object(%{a: Zoi.integer() |> Zoi.nullable() |> Zoi.default(1)}),
             Zoi.object(%{b: Zoi.integer() |> Zoi.default(2)})
           ])
       })
       |> Zoi.default(%{nested: %{a: 1, b: 2}})}
    end

    @impl true
    def reduce(reduction, _opts), do: {:ok, reduction.signal.data.owned}
  end

  test "Plugin output preserves nullable fields and cannot fill missing stored fields", c do
    definition =
      Agent.new!(
        name: "intersection_plugin",
        plugins: [Owned],
        routes: [{"intersection.reduce", Keep}]
      )

    agent = Agent.instantiate!(definition, id: unique_id("intersection"))
    {:ok, server} = Jido.start_agent(c.jido, agent)
    before = AgentServer.snapshot(server)

    for owned <- [%{}, %{nested: %{}}, %{nested: %{a: 3}}, %{nested: %{b: 4}}] do
      input = signal("intersection.reduce", %{owned: owned})
      assert {:error, _} = Agent.cmd(agent, input)
      assert {:error, _} = AgentServer.call(server, input)
      assert AgentServer.snapshot(server) === before
    end

    owned = %{nested: %{a: nil, b: 7}}
    input = signal("intersection.reduce", %{owned: owned})
    assert {:ok, direct, []} = Agent.cmd(agent, input)
    assert {:ok, live} = AgentServer.call(server, input)
    assert direct.state.owned === owned
    assert live.state === direct.state
    assert Agent.validate_instance(live) === {:ok, live}
  end
end
