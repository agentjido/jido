defmodule Jido.Agent.Server.OptionsTest do
  use JidoTest.Case, async: true
  alias Jido.Agent.Server.Options
  alias JidoTest.TestAgents.{MinimalAgent, BasicAgent}
  alias Jido.Tools.Basic.{Log, Sleep, Noop}

  describe "validate_server_opts/1" do
    test "validates minimal valid options" do
      opts = [
        agent: MinimalAgent,
        id: "test-agent"
      ]

      assert {:ok, validated} = Options.validate_server_opts(opts)
      assert Keyword.get(validated, :agent) == MinimalAgent
      assert Keyword.get(validated, :mode) == :auto
      assert Keyword.get(validated, :log_level) == :info
      assert Keyword.get(validated, :max_queue_size) == 10_000
    end

    test "validates full options set" do
      opts = [
        agent: BasicAgent,
        id: "test-agent",
        mode: :step,
        log_level: :debug,
        max_queue_size: 100,
        registry: MyRegistry,
        dispatch: {:logger, [level: :info]},
        routes: [],
        sensors: [],
        skills: [],
        child_specs: []
      ]

      assert {:ok, validated} = Options.validate_server_opts(opts)
      assert Keyword.get(validated, :agent) == BasicAgent
      assert Keyword.get(validated, :mode) == :step
      assert Keyword.get(validated, :log_level) == :debug
      assert Keyword.get(validated, :max_queue_size) == 100
      assert Keyword.get(validated, :registry) == MyRegistry
    end

    test "passes through unknown options" do
      opts = [
        agent: MinimalAgent,
        id: "test-agent",
        custom_option: "custom value",
        another_option: 123
      ]

      assert {:ok, validated} = Options.validate_server_opts(opts)
      assert Keyword.get(validated, :agent) == MinimalAgent
      assert Keyword.get(validated, :id) == "test-agent"
      assert Keyword.get(validated, :custom_option) == "custom value"
      assert Keyword.get(validated, :another_option) == 123
    end

    test "returns error for missing required options" do
      assert {:error, _} = Options.validate_server_opts([])
      assert {:error, _} = Options.validate_server_opts(agent: MinimalAgent)
      assert {:error, _} = Options.validate_server_opts(id: "test-agent")
    end

    test "returns error for invalid option values" do
      opts = [
        agent: MinimalAgent,
        id: "test-agent",
        mode: :invalid,
        log_level: :trace,
        max_queue_size: -1
      ]

      assert {:error, _} = Options.validate_server_opts(opts)
    end
  end

  describe "validate_agent_opts/1" do
    test "validates atom module" do
      assert {:ok, MinimalAgent} = Options.validate_agent_opts(MinimalAgent)
    end

    test "validates agent struct" do
      agent = MinimalAgent.new("test-agent")
      assert {:ok, ^agent} = Options.validate_agent_opts(agent)
    end

    test "returns error for invalid agent" do
      assert {:error, :invalid_agent} = Options.validate_agent_opts("invalid")
      assert {:error, :invalid_agent} = Options.validate_agent_opts(%{})
    end
  end

  describe "validate_dispatch_opts/1" do
    test "validates default dispatch configuration" do
      assert {:ok, validated} = Options.validate_dispatch_opts({:logger, [level: :info]})
      assert validated == {:logger, [level: :info]}
    end

    test "validates custom dispatch configuration" do
      config = {:pid, [target: self(), delivery_mode: :async]}
      assert {:ok, validated} = Options.validate_dispatch_opts(config)
      assert elem(validated, 0) == :pid
      assert Keyword.equal?(elem(validated, 1), target: self(), delivery_mode: :async)
    end
  end

  describe "validate_route_opts/1" do
    test "validates empty routes" do
      assert {:ok, []} = Options.validate_route_opts([])
    end

    test "returns error for invalid route format" do
      assert {:error, _} = Options.validate_route_opts([{"invalid"}])
      assert {:error, _} = Options.validate_route_opts([{:not_a_string, fn -> :ok end}])
    end
  end

  describe "validate_actions_opts/1" do
    test "validates valid action modules" do
      # Test with a single action
      assert {:ok, [Log]} = Options.validate_actions_opts([Log])

      # Test with multiple actions
      assert {:ok, [Log, Sleep, Noop]} = Options.validate_actions_opts([Log, Sleep, Noop])
    end

    test "returns error for invalid action modules" do
      # Test with a module that doesn't implement the Jido.Action behavior
      assert {:error, _} = Options.validate_actions_opts([String])

      # Test with a non-existent module
      assert {:error, _} = Options.validate_actions_opts([NonExistentModule])
    end
  end
end
