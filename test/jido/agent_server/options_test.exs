defmodule JidoTest.AgentServer.OptionsTest do
  use ExUnit.Case, async: true

  alias Jido.AgentServer.{Options, ParentRef}

  # Common options with required :jido field
  @base_opts [jido: :test_jido]

  defmodule ValidAgent do
    @moduledoc false
    use Jido.Agent,
      name: "valid_agent",
      schema: [value: [type: :integer, default: 0]]
  end

  describe "new/1 with keyword list" do
    test "creates options with agent module" do
      {:ok, opts} = Options.new(@base_opts ++ [agent: ValidAgent])

      assert opts.agent == ValidAgent
      assert is_binary(opts.id)
      assert opts.initial_state == %{}
      assert opts.registry == :"Elixir.test_jido.Registry"
      assert opts.register_global == true
      assert opts.error_policy == :log_only
      assert opts.max_queue_size == 10_000
      assert opts.on_parent_death == :stop
    end

    test "creates options with custom id" do
      {:ok, opts} = Options.new(@base_opts ++ [agent: ValidAgent, id: "custom-id"])

      assert opts.id == "custom-id"
    end

    test "creates options with initial_state" do
      {:ok, opts} = Options.new(@base_opts ++ [agent: ValidAgent, initial_state: %{foo: :bar}])

      assert opts.initial_state == %{foo: :bar}
    end

    test "registry is derived from jido instance" do
      {:ok, opts} = Options.new(@base_opts ++ [agent: ValidAgent])

      # Registry is derived from jido instance name
      assert opts.registry == :"Elixir.test_jido.Registry"
    end

    test "explicit registry is preserved when provided" do
      {:ok, opts} =
        Options.new(@base_opts ++ [agent: ValidAgent, registry: JidoTest.CustomRegistry])

      assert opts.registry == JidoTest.CustomRegistry
    end

    test "allows disabling global registration" do
      {:ok, opts} = Options.new(@base_opts ++ [agent: ValidAgent, register_global: false])

      assert opts.register_global == false
    end

    test "creates options with default_dispatch" do
      {:ok, opts} =
        Options.new(@base_opts ++ [agent: ValidAgent, default_dispatch: {:logger, level: :info}])

      assert opts.default_dispatch == {:logger, level: :info}
    end

    test "creates options with max_queue_size" do
      {:ok, opts} = Options.new(@base_opts ++ [agent: ValidAgent, max_queue_size: 100])

      assert opts.max_queue_size == 100
    end

    test "creates options with on_parent_death" do
      {:ok, opts} = Options.new(@base_opts ++ [agent: ValidAgent, on_parent_death: :continue])

      assert opts.on_parent_death == :continue
    end

    test "creates options with spawn_fun" do
      spawn_fun = fn _ -> {:ok, self()} end
      {:ok, opts} = Options.new(@base_opts ++ [agent: ValidAgent, spawn_fun: spawn_fun])

      assert opts.spawn_fun == spawn_fun
    end
  end

  describe "new/1 with map" do
    test "creates options from map" do
      {:ok, opts} = Options.new(%{jido: :test_jido, agent: ValidAgent, id: "map-test"})

      assert opts.agent == ValidAgent
      assert opts.id == "map-test"
    end
  end

  describe "new!/1" do
    test "returns options on success" do
      opts = Options.new!(@base_opts ++ [agent: ValidAgent])

      assert opts.agent == ValidAgent
    end

    test "raises on error" do
      assert_raise Jido.Error.ValidationError, fn ->
        Options.new!(@base_opts ++ [agent: nil])
      end
    end
  end

  describe "agent validation" do
    test "requires agent" do
      {:error, error} = Options.new(@base_opts)

      assert error.message =~ "agent is required"
    end

    test "rejects nil agent" do
      {:error, error} = Options.new(@base_opts ++ [agent: nil])

      assert error.message =~ "agent is required"
    end

    test "accepts agent struct" do
      agent = ValidAgent.new()
      {:ok, opts} = Options.new(@base_opts ++ [agent: agent])

      assert opts.agent == agent
    end

    test "rejects non-module non-struct agent" do
      {:error, error} = Options.new(@base_opts ++ [agent: "not_an_agent"])

      assert error.message =~ "must be a module or struct"
    end

    test "rejects module without new function" do
      {:error, error} = Options.new(@base_opts ++ [agent: Enum])

      assert error.message =~ "must implement new/0, new/1, or new/2"
    end

    test "rejects non-existent module" do
      {:error, error} = Options.new(@base_opts ++ [agent: NonExistentModule])

      assert error.message =~ "not found"
    end

    test "accepts agent_module for struct agents" do
      agent = ValidAgent.new()
      {:ok, opts} = Options.new(@base_opts ++ [agent: agent, agent_module: ValidAgent])

      assert opts.agent_module == ValidAgent
    end
  end

  describe "ID handling" do
    test "generates ID when not provided" do
      {:ok, opts} = Options.new(@base_opts ++ [agent: ValidAgent])

      assert is_binary(opts.id)
      assert String.length(opts.id) > 0
    end

    test "uses provided ID" do
      {:ok, opts} = Options.new(@base_opts ++ [agent: ValidAgent, id: "explicit-id"])

      assert opts.id == "explicit-id"
    end

    test "converts atom ID to string" do
      {:ok, opts} = Options.new(@base_opts ++ [agent: ValidAgent, id: :atom_id])

      assert opts.id == "atom_id"
    end

    test "extracts ID from agent struct" do
      agent = ValidAgent.new(id: "agent-struct-id")
      {:ok, opts} = Options.new(@base_opts ++ [agent: agent])

      assert opts.id == "agent-struct-id"
    end

    test "prefers explicit ID over agent struct ID" do
      agent = ValidAgent.new(id: "agent-id")
      {:ok, opts} = Options.new(@base_opts ++ [agent: agent, id: "explicit-id"])

      assert opts.id == "explicit-id"
    end

    test "handles empty string ID by generating one" do
      {:ok, opts} = Options.new(@base_opts ++ [agent: ValidAgent, id: ""])

      assert is_binary(opts.id)
      assert opts.id != ""
    end
  end

  describe "error policy validation" do
    test "accepts :log_only" do
      {:ok, opts} = Options.new(@base_opts ++ [agent: ValidAgent, error_policy: :log_only])

      assert opts.error_policy == :log_only
    end

    test "accepts :stop_on_error" do
      {:ok, opts} = Options.new(@base_opts ++ [agent: ValidAgent, error_policy: :stop_on_error])

      assert opts.error_policy == :stop_on_error
    end

    test "accepts {:emit_signal, config}" do
      policy = {:emit_signal, {:logger, level: :error}}
      {:ok, opts} = Options.new(@base_opts ++ [agent: ValidAgent, error_policy: policy])

      assert opts.error_policy == policy
    end

    test "accepts {:max_errors, n}" do
      {:ok, opts} =
        Options.new(@base_opts ++ [agent: ValidAgent, error_policy: {:max_errors, 5}])

      assert opts.error_policy == {:max_errors, 5}
    end

    test "accepts function/2" do
      policy = fn _error, state -> {:ok, state} end
      {:ok, opts} = Options.new(@base_opts ++ [agent: ValidAgent, error_policy: policy])

      assert opts.error_policy == policy
    end

    test "rejects invalid error policy" do
      {:error, error} = Options.new(@base_opts ++ [agent: ValidAgent, error_policy: :invalid])

      assert error.message =~ "invalid error_policy"
    end

    test "rejects {:max_errors, 0}" do
      {:error, error} =
        Options.new(@base_opts ++ [agent: ValidAgent, error_policy: {:max_errors, 0}])

      assert error.message =~ "invalid error_policy"
    end

    test "rejects {:max_errors, -1}" do
      {:error, error} =
        Options.new(@base_opts ++ [agent: ValidAgent, error_policy: {:max_errors, -1}])

      assert error.message =~ "invalid error_policy"
    end

    test "defaults to :log_only when nil" do
      {:ok, opts} = Options.new(@base_opts ++ [agent: ValidAgent, error_policy: nil])

      assert opts.error_policy == :log_only
    end
  end

  describe "parent validation" do
    test "accepts nil parent" do
      {:ok, opts} = Options.new(@base_opts ++ [agent: ValidAgent, parent: nil])

      assert opts.parent == nil
    end

    test "accepts ParentRef struct" do
      parent = ParentRef.new!(%{pid: self(), id: "parent-1", tag: :worker})
      {:ok, opts} = Options.new(@base_opts ++ [agent: ValidAgent, parent: parent])

      assert opts.parent == parent
    end

    test "accepts parent as map and converts to ParentRef" do
      {:ok, opts} =
        Options.new(
          @base_opts ++
            [agent: ValidAgent, parent: %{pid: self(), id: "parent-2", tag: :child}]
        )

      assert %ParentRef{} = opts.parent
      assert opts.parent.id == "parent-2"
      assert opts.parent.tag == :child
    end

    test "rejects invalid parent" do
      {:error, error} = Options.new(@base_opts ++ [agent: ValidAgent, parent: "invalid"])

      assert error.message =~ "parent"
    end
  end

  describe "max_queue_size validation" do
    test "accepts positive integer" do
      {:ok, opts} = Options.new(@base_opts ++ [agent: ValidAgent, max_queue_size: 500])

      assert opts.max_queue_size == 500
    end

    test "defaults to 10_000" do
      {:ok, opts} = Options.new(@base_opts ++ [agent: ValidAgent])

      assert opts.max_queue_size == 10_000
    end
  end

  describe "validate_error_policy/1" do
    test "validates all policy types" do
      assert {:ok, :log_only} = Options.validate_error_policy(:log_only)
      assert {:ok, :stop_on_error} = Options.validate_error_policy(:stop_on_error)
      assert {:ok, {:emit_signal, :cfg}} = Options.validate_error_policy({:emit_signal, :cfg})
      assert {:ok, {:max_errors, 3}} = Options.validate_error_policy({:max_errors, 3})

      fun = fn _, s -> {:ok, s} end
      assert {:ok, ^fun} = Options.validate_error_policy(fun)
    end
  end
end
