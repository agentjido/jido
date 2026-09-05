defmodule Jido.Agent.StateBudgetTest do
  use JidoTest.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.{Builder, Codec, StateBudget}
  alias Jido.AgentServer, as: Server
  alias Jido.Error.ValidationError
  alias Jido.Examples.PersistenceProbeStore, as: Store

  defmodule Write do
    use Jido.Action,
      name: "budget_write",
      schema: Zoi.object(%{payload: Zoi.string(), stop: Zoi.boolean() |> Zoi.default(false)})

    def run(%{payload: payload, stop: stop}, %{agent_state: state}) do
      directives = if stop, do: [%Jido.Agent.Directive.Stop{reason: :normal}], else: []
      {:ok, %{state | payload: payload}, directives}
    end
  end

  defmodule Bounded do
    use Jido.Agent,
      name: "budget_bounded",
      max_state_size: 128,
      schema: Zoi.object(%{payload: Zoi.string() |> Zoi.default("")}),
      routes: [{"write", Write}]
  end

  defmodule BlockBounded do
    use Jido.Agent, name: "budget_block"

    agent do
      max_state_size 128
      schema Zoi.object(%{payload: Zoi.string() |> Zoi.default("")})
    end
  end

  defmodule Owned do
    use Jido.Plugin
    def state_spec(_opts), do: {:owned, Zoi.string() |> Zoi.default("")}
    def update_state(_state, _directives, _opts), do: {:ok, String.duplicate("p", 128)}
  end

  defmodule CustomRestore do
    use Jido.Agent,
      name: "budget_custom_restore",
      max_state_size: 128,
      schema: Zoi.object(%{payload: Zoi.string() |> Zoi.default("")})

    def restore(checkpoint, _context) do
      {:ok, %{new!(id: checkpoint.id) | state: checkpoint.state, max_state_size: nil}}
    end
  end

  defp definition(limit) do
    Agent.new!(
      name: "budget_map",
      schema: Bounded.schema(),
      max_state_size: limit,
      routes: [{"write", Write}]
    )
  end

  test "the complete state accepts its exact external byte size" do
    state = %{payload: "abc"}
    size = :erlang.external_size(state)
    assert {:ok, agent} = Agent.instantiate(definition(size), state: state)
    assert StateBudget.check(agent) == {:ok, agent}

    assert {:error, %ValidationError{kind: :state_size, subject: :state, details: details}} =
             Agent.instantiate(definition(size - 1), state: state)

    assert details == %{max_state_size: size - 1, actual_state_size: size}
  end

  test "nil accepts large state and invalid limits return a structured error" do
    assert {:ok, _} =
             Agent.instantiate(definition(nil), state: %{payload: String.duplicate("x", 10_000)})

    for limit <- [-1, 1.5, "128", :infinity] do
      assert {:error, %ValidationError{kind: :state_size}} =
               Agent.new(name: "invalid_budget", max_state_size: limit)
    end

    assert {:error, %ValidationError{kind: :state_size}} = Agent.instantiate(definition(0))
  end

  test "module limits still apply when a struct loses or raises its configured limit" do
    agent = Bounded.new!()

    for limit <- [nil, 10_000] do
      forged = %{agent | max_state_size: limit, state: %{payload: String.duplicate("x", 128)}}
      assert {:error, %ValidationError{kind: :state_size}} = Agent.validate_instance(forged)
    end

    assert StateBudget.limit(%{agent | max_state_size: 64}) == 64
  end

  test "a replacement retains the prior module and smaller limit" do
    agent = Agent.instantiate!(definition(64))

    candidate = %{
      agent
      | max_state_size: nil,
        module: Bounded,
        state: %{payload: String.duplicate("x", 64)}
    }

    assert {:error, %ValidationError{details: %{max_state_size: 64}}} =
             StateBudget.transition(agent, candidate)

    assert {:ok, accepted} = StateBudget.transition(agent, %{candidate | state: %{payload: "a"}})
    assert accepted.module == agent.module
    assert accepted.max_state_size == 64
  end

  test "set and transition reject growth and permit smaller valid state" do
    agent = Bounded.new!(state: %{payload: "initial"})
    large = String.duplicate("x", 128)
    assert {:error, %ValidationError{kind: :state_size}} = Agent.set(agent, payload: large)

    assert {:error, %ValidationError{kind: :state_size}} =
             Agent.transition(agent, %{payload: large})

    assert {:ok, smaller} = Agent.set(agent, payload: "")
    assert smaller.state == %{payload: ""}
    assert agent.state == %{payload: "initial"}
  end

  test "direct commands reject oversized output and its stop directive" do
    agent = Bounded.new!()

    assert {:error, %ValidationError{kind: :state_size}} =
             Agent.cmd(agent, signal("write", %{payload: String.duplicate("x", 128), stop: true}))

    assert {:ok, next, []} = Agent.cmd(agent, signal("write", %{payload: "ok"}))
    assert next.state == %{payload: "ok"}
  end

  test "live calls and casts retain the commit and discard rejected directives", %{jido: jido} do
    observer = self()

    policy = fn reason, outcome ->
      send(observer, {:budget_error, reason, outcome})
      :continue
    end

    {:ok, server} = Jido.start_agent(jido, Bounded, error_policy: policy)
    before = Server.snapshot(server)
    invalid = signal("write", %{payload: String.duplicate("x", 128), stop: true})
    assert {:error, %ValidationError{kind: :state_size}} = Server.call(server, invalid)
    assert_receive {:budget_error, %ValidationError{kind: :state_size}, first}, 1_000
    refute first.committed?
    assert :ok = Server.cast(server, invalid)
    assert_receive {:budget_error, %ValidationError{kind: :state_size}, second}, 1_000
    refute second.committed?
    assert Process.alive?(server)
    assert Server.snapshot(server) == before
    assert {:ok, valid} = Server.call(server, signal("write", %{payload: "ok"}))
    assert Server.snapshot(server) == %{agent: valid, state_version: 1}
  end

  test "initial state and prebuilt instances cannot bypass the limit", %{jido: jido} do
    large = %{payload: String.duplicate("x", 128)}
    assert {:error, %ValidationError{kind: :state_size}} = Bounded.new(state: large)
    assert {:error, _} = Jido.start_agent(jido, Bounded, initial_state: large)
    forged = %{Bounded.new!() | state: large, max_state_size: nil}
    assert {:error, _} = Jido.start_agent(jido, forged)
    assert Jido.list_agents(jido) == []
  end

  test "the limit includes Plugin state after finalization" do
    definition = %{definition(128) | plugins: [Owned]}
    agent = Agent.instantiate!(definition)
    assert agent.state == %{payload: "", owned: ""}

    assert {:error, %ValidationError{kind: :state_size}} =
             Agent.cmd(agent, signal("write", %{payload: "ok"}))

    assert {:error, %ValidationError{kind: :state_size}} =
             Agent.instantiate(definition, state: %{owned: String.duplicate("x", 128)})
  end

  test "map Builder and block definitions retain the same limit through Codec" do
    assert Bounded.max_state_size() == 128
    assert BlockBounded.max_state_size() == 128

    builder =
      Builder.new(name: "budget_map")
      |> Builder.schema(Bounded.schema())
      |> Builder.max_state_size(128)

    assert {:ok, built} = Builder.build(builder)
    assert built.max_state_size == BlockBounded.agent().max_state_size

    for definition <- [definition(128), built, BlockBounded.agent()] do
      assert {:ok, document, registry} = Codec.encode(definition)
      assert document["max_state_size"] == 128
      assert {:ok, ^definition} = Codec.decode(document, registry)

      assert {:error, %ValidationError{kind: :state_size}} =
               Codec.decode(Map.put(document, "max_state_size", "128"), registry)

      assert {:error, _} =
               Codec.decode(document, registry, state: %{payload: String.duplicate("x", 128)})
    end

    assert {:ok, document, registry} = Codec.encode(definition(nil))
    refute Map.has_key?(document, "max_state_size")
    assert {:ok, restored} = Codec.decode(document, registry)
    assert is_nil(restored.max_state_size)
  end

  test "default and custom restore callbacks enforce the current module limit" do
    for module <- [Bounded, CustomRestore] do
      agent = module.new!()
      assert {:ok, checkpoint} = Agent.checkpoint(agent)
      assert {:ok, restored} = Agent.restore(module, checkpoint)
      assert restored.state == agent.state
      assert restored.module == module
      oversized = %{checkpoint | state: %{payload: String.duplicate("x", 128)}}
      assert {:error, %ValidationError{kind: :state_size}} = Agent.restore(module, oversized)
    end
  end

  test "generic checkpoints retain their authored limit" do
    agent = Agent.instantiate!(definition(128))
    assert {:ok, checkpoint} = Agent.checkpoint(agent)
    assert {:ok, ^agent} = Agent.restore(Agent, checkpoint)
    plain = %{checkpoint | definition: Agent.to_map(checkpoint.definition)}
    assert {:ok, ^agent} = Agent.restore(Agent, plain)

    assert {:error, %ValidationError{kind: :state_size}} =
             Agent.restore(Agent, %{plain | state: %{payload: String.duplicate("x", 128)}})
  end

  test "a valid persistence envelope cannot hide state over the current limit" do
    store = {Store, store: start_supervised!(Store)}
    agent = Bounded.new!()
    assert :ok = Jido.Persistence.save_agent(store, agent)
    assert {:ok, ^agent} = Jido.Persistence.load_agent(store, Bounded, agent.id)

    assert :ok =
             Store.rewrite_record(store, Bounded, agent.id, fn record ->
               put_in(record.checkpoint.state.payload, String.duplicate("x", 128))
             end)

    assert {:error, _} = Jido.Persistence.load_agent(store, Bounded, agent.id)
  end

  test "local runtime checkpoints cannot bypass the module limit", %{jido: jido} do
    agent = Bounded.new!()
    forged = %{agent | state: %{payload: String.duplicate("x", 128)}, max_state_size: nil}

    assert :ok =
             Jido.RuntimeStore.put(jido, :agent_runtime_checkpoints, agent.id, %{
               agent: forged,
               state_version: 4
             })

    assert {:error, _} = Jido.start_agent(jido, Bounded, id: agent.id)
    assert Jido.list_agents(jido) == []
  end
end
