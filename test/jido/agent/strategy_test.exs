defmodule JidoTest.Agent.StrategyTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Strategy
  alias Jido.Agent.Strategy.Snapshot

  defmodule TestStrategy do
    @moduledoc false
    use Jido.Agent.Strategy

    @impl true
    def cmd(agent, instructions, _ctx) do
      count = Map.get(agent.state, :cmd_count, 0)
      new_state = Map.put(agent.state, :cmd_count, count + length(instructions))
      {%{agent | state: new_state}, []}
    end

    @impl true
    def action_spec(:special_action) do
      %{
        schema: Zoi.object(%{value: Zoi.integer()}, coerce: true),
        doc: "A special action",
        name: "special_action"
      }
    end

    def action_spec(:simple_action) do
      %{
        schema: [value: [type: :integer, required: true]],
        doc: "A simple action"
      }
    end

    def action_spec(_), do: nil

    @impl true
    def signal_routes(_ctx) do
      [
        {"test.action", {:strategy_cmd, :test_action}},
        {"test.tick", {:strategy_tick}},
        {"test.custom", {:custom, :my_handler}}
      ]
    end
  end

  defmodule MinimalStrategy do
    @moduledoc false
    use Jido.Agent.Strategy

    @impl true
    def cmd(agent, _instructions, _ctx), do: {agent, []}
  end

  describe "Snapshot" do
    test "terminal?/1 returns true for success and failure" do
      assert Snapshot.terminal?(%Snapshot{status: :success, done?: true})
      assert Snapshot.terminal?(%Snapshot{status: :failure, done?: true})
    end

    test "terminal?/1 returns false for other statuses" do
      refute Snapshot.terminal?(%Snapshot{status: :idle, done?: false})
      refute Snapshot.terminal?(%Snapshot{status: :running, done?: false})
      refute Snapshot.terminal?(%Snapshot{status: :waiting, done?: false})
    end

    test "running?/1 returns true for running and waiting" do
      assert Snapshot.running?(%Snapshot{status: :running, done?: false})
      assert Snapshot.running?(%Snapshot{status: :waiting, done?: false})
    end

    test "running?/1 returns false for other statuses" do
      refute Snapshot.running?(%Snapshot{status: :idle, done?: false})
      refute Snapshot.running?(%Snapshot{status: :success, done?: true})
      refute Snapshot.running?(%Snapshot{status: :failure, done?: true})
    end
  end

  describe "default_snapshot/1" do
    test "returns snapshot with default values" do
      {:ok, agent} = Agent.new(%{id: "test"})
      snapshot = Strategy.default_snapshot(agent)

      assert %Snapshot{} = snapshot
      assert snapshot.status == :idle
      assert snapshot.done? == false
      assert snapshot.result == nil
      assert snapshot.details == %{}
    end

    test "returns snapshot with strategy state" do
      {:ok, agent} =
        Agent.new(%{
          id: "test",
          state: %{
            __strategy__: %{
              status: :success,
              result: "the answer",
              custom_field: :custom_value,
              config: %{some: :config}
            }
          }
        })

      snapshot = Strategy.default_snapshot(agent)

      assert snapshot.status == :success
      assert snapshot.done? == true
      assert snapshot.result == "the answer"
      assert snapshot.details == %{custom_field: :custom_value}
    end
  end

  describe "normalize_instruction/3" do
    test "preserves string keys when no action_spec (atom-safe)" do
      {:ok, _agent} = Agent.new(%{id: "test"})

      instruction = %Jido.Instruction{
        action: :unknown_action,
        params: %{"foo" => "bar", "nested" => %{"key" => "value"}}
      }

      ctx = %{agent_module: nil, strategy_opts: []}
      normalized = Strategy.normalize_instruction(MinimalStrategy, instruction, ctx)

      # Keys remain as strings to prevent atom table exhaustion
      assert normalized.params["foo"] == "bar"
      assert normalized.params["nested"] == %{"key" => "value"}
    end

    test "normalizes with Zoi schema" do
      {:ok, _agent} = Agent.new(%{id: "test"})

      instruction = %Jido.Instruction{
        action: :special_action,
        params: %{"value" => 42}
      }

      ctx = %{agent_module: nil, strategy_opts: []}
      normalized = Strategy.normalize_instruction(TestStrategy, instruction, ctx)

      assert normalized.params.value == 42
    end

    test "normalizes with NimbleOptions schema" do
      {:ok, _agent} = Agent.new(%{id: "test"})

      instruction = %Jido.Instruction{
        action: :simple_action,
        params: %{"value" => 42}
      }

      ctx = %{agent_module: nil, strategy_opts: []}
      normalized = Strategy.normalize_instruction(TestStrategy, instruction, ctx)

      assert normalized.params[:value] == 42
    end

    test "raises on invalid params for Zoi schema" do
      instruction = %Jido.Instruction{
        action: :special_action,
        params: %{"value" => "not_a_number_that_can_be_parsed"}
      }

      ctx = %{agent_module: nil, strategy_opts: []}

      assert_raise ArgumentError, ~r/Invalid params/, fn ->
        Strategy.normalize_instruction(TestStrategy, instruction, ctx)
      end
    end

    test "handles already-atom keys" do
      instruction = %Jido.Instruction{
        action: :unknown_action,
        params: %{foo: "bar", baz: 123}
      }

      ctx = %{agent_module: nil, strategy_opts: []}
      normalized = Strategy.normalize_instruction(MinimalStrategy, instruction, ctx)

      assert normalized.params.foo == "bar"
      assert normalized.params.baz == 123
    end

    test "handles non-map params" do
      instruction = %Jido.Instruction{
        action: :unknown_action,
        params: "just a string"
      }

      ctx = %{agent_module: nil, strategy_opts: []}
      normalized = Strategy.normalize_instruction(MinimalStrategy, instruction, ctx)

      assert normalized.params == "just a string"
    end
  end

  describe "__using__/1 macro" do
    test "provides default init/2 implementation" do
      {:ok, agent} = Agent.new(%{id: "test"})
      ctx = %{agent_module: nil, strategy_opts: []}

      {result_agent, directives} = MinimalStrategy.init(agent, ctx)

      assert result_agent == agent
      assert directives == []
    end

    test "provides default tick/2 implementation" do
      {:ok, agent} = Agent.new(%{id: "test"})
      ctx = %{agent_module: nil, strategy_opts: []}

      {result_agent, directives} = MinimalStrategy.tick(agent, ctx)

      assert result_agent == agent
      assert directives == []
    end

    test "provides default snapshot/2 implementation" do
      {:ok, agent} = Agent.new(%{id: "test"})
      ctx = %{agent_module: nil, strategy_opts: []}

      snapshot = MinimalStrategy.snapshot(agent, ctx)

      assert %Snapshot{} = snapshot
      assert snapshot.status == :idle
    end
  end

  describe "custom strategy implementation" do
    test "cmd/3 is called properly" do
      {:ok, agent} = Agent.new(%{id: "test"})
      ctx = %{agent_module: nil, strategy_opts: []}

      instructions = [
        %Jido.Instruction{action: :action1, params: %{}},
        %Jido.Instruction{action: :action2, params: %{}}
      ]

      {updated_agent, directives} = TestStrategy.cmd(agent, instructions, ctx)

      assert updated_agent.state.cmd_count == 2
      assert directives == []
    end

    test "action_spec/1 returns spec for known actions" do
      spec = TestStrategy.action_spec(:special_action)

      assert spec[:doc] == "A special action"
      assert spec[:name] == "special_action"
      assert spec[:schema] != nil
    end

    test "action_spec/1 returns nil for unknown actions" do
      assert nil == TestStrategy.action_spec(:unknown_action)
    end

    test "signal_routes/1 returns route definitions" do
      ctx = %{agent_module: nil, strategy_opts: []}
      routes = TestStrategy.signal_routes(ctx)

      assert length(routes) == 3
      assert {"test.action", {:strategy_cmd, :test_action}} in routes
      assert {"test.tick", {:strategy_tick}} in routes
      assert {"test.custom", {:custom, :my_handler}} in routes
    end
  end

  describe "atom-safe key handling" do
    test "preserves mixed key types without atomization" do
      instruction = %Jido.Instruction{
        action: :unknown_action,
        params: %{
          :atom_key => "value1",
          "string_key" => "value2",
          123 => "value3"
        }
      }

      ctx = %{agent_module: nil, strategy_opts: []}
      normalized = Strategy.normalize_instruction(MinimalStrategy, instruction, ctx)

      # Existing atom keys remain atoms, string keys stay strings (atom-safe)
      assert normalized.params.atom_key == "value1"
      assert normalized.params["string_key"] == "value2"
      assert normalized.params[123] == "value3"
    end
  end
end
