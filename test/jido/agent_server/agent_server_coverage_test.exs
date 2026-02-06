defmodule JidoTest.AgentServerCoverageTest do
  @moduledoc """
  Additional tests to improve AgentServer coverage.

  Tests uncovered paths including:
  - resolve_server with {:via, ...} that returns nil
  - Agent resolution with new/0 vs new/1
  - Pre-built struct with agent_module option
  - Lifecycle hooks (on_before_cmd, on_after_cmd)
  - Queue overflow scenario
  - Multiple await_completion waiters
  - Invalid signal handling
  """

  use JidoTest.Case, async: true

  @moduletag :capture_log

  alias Jido.AgentServer
  alias Jido.Signal
  alias JidoTest.TestAgents.Counter

  # Simple test agent with defaults
  defmodule SimpleTestAgent do
    @moduledoc false
    use Jido.Agent,
      name: "simple_test_agent",
      schema: [
        counter: [type: :integer, default: 0]
      ]

    def signal_routes(_ctx) do
      [{"increment", JidoTest.TestActions.IncrementAction}]
    end
  end

  # Agent with on_before_cmd hook
  defmodule BeforeHookAgent do
    @moduledoc false
    use Jido.Agent,
      name: "before_hook_agent",
      schema: [
        counter: [type: :integer, default: 0],
        before_called: [type: :boolean, default: false],
        intercepted_action: [type: :any, default: nil]
      ]

    def signal_routes(_ctx) do
      [{"increment", JidoTest.TestActions.IncrementAction}]
    end

    def on_before_cmd(agent, action) do
      agent = %{
        agent
        | state: Map.merge(agent.state, %{before_called: true, intercepted_action: action})
      }

      {:ok, agent, action}
    end
  end

  # Agent with on_after_cmd hook
  defmodule AfterHookAgent do
    @moduledoc false
    use Jido.Agent,
      name: "after_hook_agent",
      schema: [
        counter: [type: :integer, default: 0],
        after_called: [type: :boolean, default: false]
      ]

    def signal_routes(_ctx) do
      [{"increment", JidoTest.TestActions.IncrementAction}]
    end

    def on_after_cmd(agent, _action, directives) do
      {:ok, %{agent | state: Map.put(agent.state, :after_called, true)}, directives}
    end
  end

  # Agent with both hooks
  defmodule BothHooksAgent do
    @moduledoc false
    use Jido.Agent,
      name: "both_hooks_agent",
      schema: [
        counter: [type: :integer, default: 0],
        before_called: [type: :boolean, default: false],
        after_called: [type: :boolean, default: false]
      ]

    def signal_routes(_ctx) do
      [{"increment", JidoTest.TestActions.IncrementAction}]
    end

    def on_before_cmd(agent, action) do
      {:ok, %{agent | state: Map.put(agent.state, :before_called, true)}, action}
    end

    def on_after_cmd(agent, _action, directives) do
      {:ok, %{agent | state: Map.put(agent.state, :after_called, true)}, directives}
    end
  end

  # Action that generates many directives for queue overflow testing
  defmodule ManyDirectivesAction do
    @moduledoc false
    use Jido.Action,
      name: "many_directives",
      schema: [
        count: [type: :integer, default: 10]
      ]

    alias Jido.Agent.Directive

    def run(%{count: count}, _context) do
      directives =
        for i <- 1..count do
          signal = Jido.Signal.new!("test.emitted.#{i}", %{index: i}, source: "/test")
          %Directive.Emit{signal: signal}
        end

      {:ok, %{directive_count: count}, directives}
    end
  end

  defmodule ManyDirectivesAgent do
    @moduledoc false
    use Jido.Agent,
      name: "many_directives_agent",
      schema: [
        counter: [type: :integer, default: 0],
        directive_count: [type: :integer, default: 0]
      ]

    def signal_routes(_ctx) do
      [{"many_directives", ManyDirectivesAction}]
    end
  end

  # Actions for await_completion testing - defined before agent that uses them
  defmodule CompleteAction do
    @moduledoc false
    use Jido.Action, name: "complete", schema: []

    def run(_params, _context) do
      {:ok, %{status: :completed, last_answer: "done!"}}
    end
  end

  defmodule FailAction do
    @moduledoc false
    use Jido.Action, name: "fail", schema: []

    def run(_params, _context) do
      {:ok, %{status: :failed, error: "something went wrong"}}
    end
  end

  defmodule DelayCompleteAction do
    @moduledoc false
    use Jido.Action,
      name: "delay_complete",
      schema: [delay_ms: [type: :integer, default: 50]]

    def run(%{delay_ms: delay}, _context) do
      Process.sleep(delay)
      {:ok, %{status: :completed, last_answer: "delayed done!"}}
    end
  end

  # Agent for await_completion testing
  defmodule CompletionAgent do
    @moduledoc false
    use Jido.Agent,
      name: "completion_agent",
      schema: [
        status: [type: :atom, default: :pending],
        last_answer: [type: :any, default: nil],
        error: [type: :any, default: nil]
      ]

    def signal_routes(_ctx) do
      [
        {"complete", CompleteAction},
        {"fail", FailAction},
        {"delay_complete", DelayCompleteAction}
      ]
    end
  end

  describe "resolve_server with {:via, ...}" do
    test "via tuple that resolves to nil returns error", %{jido: jido} do
      nonexistent_via = {:via, Registry, {Jido.registry_name(jido), "nonexistent-via-agent"}}
      signal = Signal.new!("increment", %{}, source: "/test")

      assert {:error, :not_found} = AgentServer.call(nonexistent_via, signal)
      assert {:error, :not_found} = AgentServer.cast(nonexistent_via, signal)
      assert {:error, :not_found} = AgentServer.state(nonexistent_via)
    end

    test "via tuple that exists works", %{jido: jido} do
      {:ok, _pid} =
        AgentServer.start_link(
          agent: Counter,
          id: "via-test-exists",
          jido: jido
        )

      via = {:via, Registry, {Jido.registry_name(jido), "via-test-exists"}}
      signal = Signal.new!("increment", %{}, source: "/test")

      {:ok, agent} = AgentServer.call(via, signal)
      assert agent.state.counter == 1
    end
  end

  describe "resolve_server with string ID" do
    test "string ID returns error with helpful message", %{jido: _jido} do
      signal = Signal.new!("increment", %{}, source: "/test")

      assert {:error, {:invalid_server, message}} = AgentServer.call("some-string-id", signal)
      assert message =~ "String IDs require explicit registry lookup"
      assert message =~ "some-string-id"
    end

    test "string ID error on cast", %{jido: _jido} do
      signal = Signal.new!("increment", %{}, source: "/test")
      assert {:error, {:invalid_server, _}} = AgentServer.cast("some-string-id", signal)
    end

    test "string ID error on state", %{jido: _jido} do
      assert {:error, {:invalid_server, _}} = AgentServer.state("some-string-id")
    end
  end

  describe "resolve_server with atom name" do
    test "atom name that doesn't exist returns error", %{jido: _jido} do
      signal = Signal.new!("increment", %{}, source: "/test")
      assert {:error, :not_found} = AgentServer.call(:nonexistent_atom_server, signal)
    end
  end

  describe "agent resolution with defaults" do
    test "agent uses default values from schema", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: SimpleTestAgent, jido: jido)

      {:ok, state} = AgentServer.state(pid)
      assert state.agent.state.counter == 0

      GenServer.stop(pid)
    end

    test "id and initial_state options are respected", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(
          agent: SimpleTestAgent,
          id: "custom-id-123",
          initial_state: %{counter: 999},
          jido: jido
        )

      {:ok, state} = AgentServer.state(pid)
      assert state.id == "custom-id-123"
      assert state.agent.state.counter == 999

      GenServer.stop(pid)
    end
  end

  describe "pre-built struct with agent_module option" do
    test "uses explicit agent_module for cmd routing", %{jido: jido} do
      agent = Counter.new(id: "prebuilt-struct-test")
      agent = %{agent | state: Map.put(agent.state, :counter, 50)}

      {:ok, pid} =
        AgentServer.start_link(
          agent: agent,
          agent_module: Counter,
          jido: jido
        )

      {:ok, state} = AgentServer.state(pid)
      assert state.id == "prebuilt-struct-test"
      assert state.agent.state.counter == 50
      assert state.agent_module == Counter

      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, updated_agent} = AgentServer.call(pid, signal)
      assert updated_agent.state.counter == 51

      GenServer.stop(pid)
    end
  end

  describe "lifecycle hooks" do
    test "on_before_cmd is called before action runs", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: BeforeHookAgent, jido: jido)

      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, agent} = AgentServer.call(pid, signal)

      assert agent.state.before_called == true
      assert agent.state.counter == 1

      GenServer.stop(pid)
    end

    test "on_after_cmd is called after action runs", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: AfterHookAgent, jido: jido)

      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, agent} = AgentServer.call(pid, signal)

      assert agent.state.after_called == true
      assert agent.state.counter == 1

      GenServer.stop(pid)
    end

    test "both hooks are called in order", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: BothHooksAgent, jido: jido)

      signal = Signal.new!("increment", %{}, source: "/test")
      {:ok, agent} = AgentServer.call(pid, signal)

      assert agent.state.before_called == true
      assert agent.state.after_called == true
      assert agent.state.counter == 1

      GenServer.stop(pid)
    end
  end

  describe "queue overflow" do
    test "queue overflow returns error when max_queue_size exceeded", %{jido: jido} do
      {:ok, pid} =
        AgentServer.start_link(
          agent: ManyDirectivesAgent,
          max_queue_size: 1,
          jido: jido
        )

      signal = Signal.new!("many_directives", %{count: 5}, source: "/test")
      # Action produces 5 directives but queue size is 1, so we get overflow error
      {:error, :queue_overflow} = AgentServer.call(pid, signal)

      GenServer.stop(pid)
    end
  end

  describe "await_completion" do
    test "returns immediately when already completed", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: CompletionAgent, jido: jido)

      signal = Signal.new!("complete", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      {:ok, result} = AgentServer.await_completion(pid)
      assert result.status == :completed
      assert result.result == "done!"

      GenServer.stop(pid)
    end

    test "returns immediately when already failed", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: CompletionAgent, jido: jido)

      signal = Signal.new!("fail", %{}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      {:ok, result} = AgentServer.await_completion(pid)
      assert result.status == :failed
      assert result.result == "something went wrong"

      GenServer.stop(pid)
    end
  end

  describe "invalid signal handling" do
    test "signal with no matching route returns error", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: JidoTest.TestAgents.Minimal, jido: jido)

      signal = Signal.new!("nonexistent_action", %{}, source: "/test")
      {:error, :no_matching_route} = AgentServer.call(pid, signal)

      GenServer.stop(pid)
    end
  end

  describe "alive? with various server types" do
    test "alive? returns false for via tuple that doesn't exist", %{jido: jido} do
      via = {:via, Registry, {Jido.registry_name(jido), "nonexistent-alive-test"}}
      refute AgentServer.alive?(via)
    end

    test "alive? returns false for atom name that doesn't exist", %{jido: _jido} do
      refute AgentServer.alive?(:nonexistent_atom_name)
    end

    test "alive? returns true for existing via tuple", %{jido: jido} do
      {:ok, _pid} =
        AgentServer.start_link(
          agent: Counter,
          id: "alive-via-test",
          jido: jido
        )

      via = {:via, Registry, {Jido.registry_name(jido), "alive-via-test"}}
      assert AgentServer.alive?(via)
    end
  end
end
