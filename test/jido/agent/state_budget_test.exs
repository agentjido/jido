defmodule JidoTest.Agent.StateBudgetTest do
  use JidoTest.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.{StateBudget, StateOp, StateOps}
  alias Jido.Agent.Directive
  alias Jido.AgentServer
  alias Jido.Error.ValidationError
  alias Jido.Signal

  @moduletag :capture_log

  defmodule Write do
    use Jido.Action, name: "budget_write", schema: []
    def run(params, _context), do: {:ok, params, [%Directive.Stop{reason: :normal}]}
  end

  defmodule Bounded do
    use Jido.Agent,
      name: "bounded",
      max_state_size: 1024,
      default_plugins: false,
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
      signal_routes: [{"write", Write}]
  end

  defmodule BeforeHook do
    use Jido.Agent, name: "before_budget", max_state_size: 1024, default_plugins: false

    def on_before_cmd(agent, action) do
      {:ok, %{agent | state: %{large: String.duplicate("x", 2048)}}, action}
    end
  end

  defmodule AfterHook do
    use Jido.Agent, name: "after_budget", max_state_size: 1024, default_plugins: false

    def on_after_cmd(agent, _action, directives) do
      {:ok, %{agent | state: %{large: String.duplicate("x", 2048)}}, directives}
    end
  end

  defmodule UncheckedStrategy do
    use Jido.Agent.Strategy

    def cmd(agent, _instructions, _ctx) do
      {%{agent | max_state_size: nil, state: %{large: String.duplicate("x", 2048)}},
       [%Directive.Stop{reason: :normal}]}
    end
  end

  defmodule StrategyAgent do
    use Jido.Agent,
      name: "strategy_budget",
      max_state_size: 1024,
      default_plugins: false,
      strategy: UncheckedStrategy
  end

  test "accepts the exact external size and rejects one byte less" do
    state = %{value: {self(), make_ref(), <<0, 255>>, [1, 2, 3]}}
    size = :erlang.external_size(state)
    assert {:ok, agent} = Agent.new(state: state, max_state_size: size)
    assert agent.state == state

    assert {:error, %ValidationError{kind: :state_size, details: details}} =
             Agent.new(state: state, max_state_size: size - 1)

    assert details == %{max_state_size: size - 1, actual_state_size: size}
  end

  test "no budget preserves unrestricted state" do
    assert {:ok, agent} = Agent.new(state: %{large: String.duplicate("x", 100_000)})
    assert agent.max_state_size == nil
    assert {:ok, _} = Agent.set(agent, %{more: String.duplicate("y", 100_000)})
  end

  test "invalid limits fail validation" do
    for limit <- [-1, "bad", 1.5] do
      assert {:error, _} = Agent.new(max_state_size: limit)
    end
  end

  test "module new keeps its struct return and rejects oversized initial state" do
    assert %Agent{max_state_size: 1024} = Bounded.new()
    assert_raise ValidationError, fn -> Bounded.new(state: %{large: large()}) end
  end

  test "both set APIs return an error without changing the input" do
    agent = Bounded.new()
    assert {:error, %ValidationError{kind: :state_size}} = Bounded.set(agent, large: large())
    assert {:error, %ValidationError{kind: :state_size}} = Agent.set(agent, large: large())
    assert agent.state == %{count: 0}
  end

  test "validation checks raw struct updates" do
    agent = %{Bounded.new() | state: %{count: 0, large: large()}}
    assert {:error, %ValidationError{kind: :state_size}} = Bounded.validate(agent)
    assert {:error, %ValidationError{kind: :state_size}} = Agent.validate(agent)
  end

  test "command failure returns original state and discards external directives" do
    agent = Bounded.new()

    assert {^agent, [%Directive.Error{context: :state_size, error: error}]} =
             Bounded.cmd(agent, {Write, %{large: large()}})

    assert error.kind == :state_size
  end

  test "before, after and custom strategy changes are bounded" do
    for module <- [BeforeHook, AfterHook, StrategyAgent] do
      agent = module.new()
      assert {^agent, [%Directive.Error{context: :state_size}]} = module.cmd(agent, Write)
    end
  end

  test "module budget cannot be removed through a struct field" do
    agent = %{Bounded.new() | max_state_size: nil}
    assert {:error, %ValidationError{kind: :state_size}} = Agent.set(agent, large: large())
  end

  test "state operations and direct results reject oversized updates" do
    agent = Bounded.new()

    for op <- [
          %StateOp.SetState{attrs: %{large: large()}},
          %StateOp.ReplaceState{state: %{large: large()}},
          %StateOp.SetPath{path: [:nested, :large], value: large()}
        ] do
      assert_raise ValidationError, fn -> StateOps.apply_state_ops(agent, [op]) end
    end

    assert_raise ValidationError, fn -> StateOps.apply_result(agent, %{large: large()}) end
  end

  test "state deletion remains available for compaction" do
    agent = Bounded.new(state: %{extra: "small"})
    {agent, []} = StateOps.apply_state_ops(agent, [%StateOp.DeleteKeys{keys: [:extra]}])
    assert agent.state == %{count: 0}
    assert {:ok, ^agent} = StateBudget.check(agent)
  end

  test "thread, memory and strategy helpers enforce the same budget" do
    agent = Bounded.new()

    assert_raise ValidationError, fn ->
      Jido.Agent.Strategy.State.put(agent, %{large: large()})
    end

    assert_raise ValidationError, fn ->
      Jido.Thread.Agent.append(agent, %{kind: :message, payload: %{text: large()}})
    end

    assert_raise ValidationError, fn ->
      Jido.Memory.Agent.put(agent, %{Jido.Memory.new() | spaces: %{large: large()}})
    end
  end

  test "restore checks the complete restored state" do
    data = %{id: "restored", state: %{large: large()}}
    assert {:error, %ValidationError{kind: :state_size}} = Bounded.restore(data, %{})
    assert {:ok, agent} = Bounded.restore(%{id: "restored", state: %{count: 3}}, %{})
    assert agent.state.count == 3
  end

  test "runtime rejects oversized initial and prebuilt state", %{jido: jido} do
    assert {:error, %ValidationError{kind: :state_size}} =
             AgentServer.start(jido: jido, agent: Bounded, initial_state: %{large: large()})

    agent = %{Bounded.new() | state: %{large: large()}}

    assert {:error, %ValidationError{kind: :state_size}} =
             AgentServer.start(jido: jido, agent: agent, agent_module: Bounded)
  end

  test "synchronous and asynchronous commands keep runtime state within budget", %{jido: jido} do
    pid = start_supervised!({AgentServer, jido: jido, agent: Bounded})
    signal = Signal.new!("write", %{large: large()}, source: "/test")
    assert {:error, %ValidationError{kind: :state_size}} = AgentServer.call(pid, signal)
    assert :ok = AgentServer.cast(pid, signal)
    assert {:ok, state} = AgentServer.state(pid)
    assert state.agent.state == %{count: 0}
    assert Process.alive?(pid)
  end

  test "persistence rejects oversized checkpoint state" do
    table = :"budget_restore_#{System.unique_integer([:positive])}"
    agent = %{Bounded.new(id: "saved") | state: %{large: large()}}
    assert :ok = Jido.Persist.hibernate({Jido.Storage.ETS, table: table}, agent)

    assert {:error, %ValidationError{kind: :state_size}} =
             Jido.Persist.thaw({Jido.Storage.ETS, table: table}, Bounded, "saved")
  end

  test "explicit runtime module enforces its budget on a generic agent", %{jido: jido} do
    {:ok, agent} = Agent.new(state: %{large: large()})

    assert {:error, %ValidationError{kind: :state_size}} =
             AgentServer.start(jido: jido, agent: agent, agent_module: Bounded)
  end

  defp large, do: String.duplicate("x", 2048)
end
