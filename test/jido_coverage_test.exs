defmodule JidoCoverageTest do
  use ExUnit.Case
  use Mimic

  @moduletag :capture_log

  defmodule TestJido do
    use Jido, otp_app: :jido_test_app
  end

  # Table-driven delegation test data
  @lifecycle_delegations [
    {:start_agent, :start_agent, [:test_agent], [[:test_agent, []]]},
    {:start_agent, :start_agent, [:test_agent, [id: "test"]], [[:test_agent, [id: "test"]]]},
    {:start_agents, :start_agents, [[:spec1, :spec2]], [[:spec1, :spec2]]},
    {:stop_agent, :stop_agent, [:agent], [[:agent, []]]},
    {:stop_agent, :stop_agent, [:agent, [timeout: 1000]], [[:agent, [timeout: 1000]]]},
    {:restart_agent, :restart_agent, [:agent], [[:agent, []]]},
    {:restart_agent, :restart_agent, [:agent, [timeout: 2000]], [[:agent, [timeout: 2000]]]},
    {:clone_agent, :clone_agent, ["src", "dst"], [["src", "dst", []]]},
    {:clone_agent, :clone_agent, ["src", "dst", [preserve: true]],
     [["src", "dst", [preserve: true]]]},
    {:get_agent, :get_agent, ["test_id"], [["test_id", []]]},
    {:get_agent, :get_agent, ["test_id", [timeout: 1000]], [["test_id", [timeout: 1000]]]},
    {:get_agent!, :get_agent!, ["test_id"], [["test_id", []]]},
    {:get_agent!, :get_agent!, ["test_id", [timeout: 1000]], [["test_id", [timeout: 1000]]]},
    {:agent_pid, :agent_pid, [:test_ref], [:test_ref]},
    {:agent_alive?, :agent_alive?, [:alive], :alive},
    {:agent_alive?, :agent_alive?, [:dead], :dead},
    {:get_agent_state, :get_agent_state, [:test_ref], :test_ref},
    {:get_agent_status, :get_agent_status, [:test_ref], :test_ref},
    {:queue_size, :queue_size, [:test], :test},
    {:list_running_agents, :list_running_agents, [], [[]]},
    {:list_running_agents, :list_running_agents, [[registry: :custom]], [[registry: :custom]]}
  ]

  @utilities_delegations [
    {:via, :via, ["test_id"], [["test_id", []]]},
    {:via, :via, ["test_id", [registry: :custom]], [["test_id", [registry: :custom]]]},
    {:resolve_pid, :resolve_pid, [:test_server], :test_server},
    {:generate_id, :generate_id, [], []},
    {:log_level, :log_level, [:agent, :debug], [:agent, :debug]}
  ]

  @discovery_delegations [
    {:list_actions, :list_actions, [], [[]]},
    {:list_actions, :list_actions, [[limit: 10]], [[limit: 10]]},
    {:list_sensors, :list_sensors, [], [[]]},
    {:list_sensors, :list_sensors, [[category: :monitoring]], [[category: :monitoring]]},
    {:list_agents, :list_agents, [], [[]]},
    {:list_agents, :list_agents, [[tag: :worker]], [[tag: :worker]]},
    {:list_skills, :list_skills, [], [[]]},
    {:list_skills, :list_skills, [[category: :utility]], [[category: :utility]]},
    {:list_demos, :list_demos, [], [[]]},
    {:list_demos, :list_demos, [[name: "example"]], [[name: "example"]]},
    {:get_action_by_slug, :get_action_by_slug, ["test-action"], "test-action"},
    {:get_sensor_by_slug, :get_sensor_by_slug, ["test-sensor"], "test-sensor"},
    {:get_agent_by_slug, :get_agent_by_slug, ["test-agent"], "test-agent"},
    {:get_skill_by_slug, :get_skill_by_slug, ["test-skill"], "test-skill"},
    {:get_demo_by_slug, :get_demo_by_slug, ["test-demo"], "test-demo"}
  ]

  describe "__using__ macro coverage" do
    test "raises error when otp_app is not provided" do
      assert_raise ArgumentError, ~r/You must provide `otp_app: :your_app`/, fn ->
        defmodule TestNoOTPApp do
          use Jido
        end
      end
    end

    test "TestJido module has proper configuration" do
      Application.put_env(:jido_test_app, TestJido, test_config: :value)
      config = TestJido.config()
      assert config[:test_config] == :value
      assert config[:agent_registry] == Jido.Registry
    end

    test "start_link delegates to ensure_started" do
      stub(Jido.Supervisor, :start_link, fn module, config ->
        assert module == TestJido
        assert is_list(config)
        {:ok, :supervisor_pid}
      end)

      assert TestJido.start_link() == {:ok, :supervisor_pid}
    end
  end

  describe "ensure_started/1 coverage" do
    test "calls Jido.Supervisor.start_link with module and config" do
      stub(Jido.Supervisor, :start_link, fn module, config ->
        send(self(), {:supervisor_called, module, config})
        {:ok, :test_pid}
      end)

      result = Jido.ensure_started(TestJido)
      assert result == {:ok, :test_pid}

      assert_received {:supervisor_called, TestJido, config}
      assert is_list(config)
    end
  end

  describe "lifecycle delegations" do
    test "all lifecycle functions delegate properly" do
      # Set up comprehensive stubs for Jido.Agent.Lifecycle
      stub(Jido.Agent.Lifecycle, :start_agent, fn
        agent, [] -> {:ok, agent}
        agent, opts -> {:ok, {agent, opts}}
      end)

      stub(Jido.Agent.Lifecycle, :start_agents, fn specs -> {:ok, specs} end)
      stub(Jido.Agent.Lifecycle, :stop_agent, fn ref, opts -> {:ok, {ref, opts}} end)
      stub(Jido.Agent.Lifecycle, :restart_agent, fn ref, opts -> {:ok, {ref, opts}} end)
      stub(Jido.Agent.Lifecycle, :clone_agent, fn src, dst, opts -> {:ok, {src, dst, opts}} end)
      stub(Jido.Agent.Lifecycle, :get_agent, fn id, opts -> {:ok, {id, opts}} end)
      stub(Jido.Agent.Lifecycle, :get_agent!, fn id, opts -> {id, opts} end)
      stub(Jido.Agent.Lifecycle, :agent_pid, fn ref -> {:pid, ref} end)

      stub(Jido.Agent.Lifecycle, :agent_alive?, fn
        :alive -> true
        :dead -> false
      end)

      stub(Jido.Agent.Lifecycle, :get_agent_state, fn ref -> {:ok, %{agent: ref}} end)
      stub(Jido.Agent.Lifecycle, :get_agent_status, fn ref -> {:ok, {:status, ref}} end)
      stub(Jido.Agent.Lifecycle, :queue_size, fn ref -> {:ok, String.length(to_string(ref))} end)
      stub(Jido.Agent.Lifecycle, :list_running_agents, fn opts -> {:opts, opts} end)

      # Test each delegation
      Enum.each(@lifecycle_delegations, fn {jido_func, _target_func, args, _expected_call} ->
        result = apply(Jido, jido_func, args)

        case {jido_func, length(args)} do
          {:start_agent, 1} ->
            assert result == {:ok, hd(args)}

          {:start_agent, 2} ->
            assert result == {:ok, List.to_tuple(args)}

          {:start_agents, _} ->
            assert result == {:ok, hd(args)}

          {:stop_agent, 1} ->
            assert result == {:ok, {hd(args), []}}

          {:stop_agent, 2} ->
            assert result == {:ok, List.to_tuple(args)}

          {:restart_agent, 1} ->
            assert result == {:ok, {hd(args), []}}

          {:restart_agent, 2} ->
            assert result == {:ok, List.to_tuple(args)}

          {:clone_agent, 2} ->
            [src, dst] = args
            assert result == {:ok, {src, dst, []}}

          {:clone_agent, 3} ->
            assert result == {:ok, List.to_tuple(args)}

          {:get_agent, 1} ->
            assert result == {:ok, {hd(args), []}}

          {:get_agent, 2} ->
            assert result == {:ok, List.to_tuple(args)}

          {:get_agent!, 1} ->
            assert result == {hd(args), []}

          {:get_agent!, 2} ->
            assert result == List.to_tuple(args)

          {:agent_pid, _} ->
            assert result == {:pid, hd(args)}

          {:agent_alive?, _} ->
            assert result == (hd(args) == :alive)

          {:get_agent_state, _} ->
            assert result == {:ok, %{agent: hd(args)}}

          {:get_agent_status, _} ->
            assert result == {:ok, {:status, hd(args)}}

          {:queue_size, _} ->
            # "test" has 4 characters
            assert result == {:ok, 4}

          {:list_running_agents, _} ->
            expected = if Enum.empty?(args), do: [], else: hd(args)
            assert result == {:opts, expected}
        end
      end)
    end
  end

  describe "utilities delegations" do
    test "all utility functions delegate properly" do
      stub(Jido.Agent.Utilities, :via, fn id, opts -> {:via, id, opts} end)
      stub(Jido.Agent.Utilities, :resolve_pid, fn server -> {:resolved, server} end)
      stub(Jido.Agent.Utilities, :generate_id, fn -> "generated_id_12345" end)
      stub(Jido.Agent.Utilities, :log_level, fn ref, level -> {:log, ref, level} end)

      # Test each delegation
      Enum.each(@utilities_delegations, fn {jido_func, _target_func, args, _expected_call} ->
        result = apply(Jido, jido_func, args)

        case {jido_func, length(args)} do
          {:via, 1} ->
            assert result == {:via, hd(args), []}

          {:via, 2} ->
            assert result == {:via, hd(args), List.last(args)}

          {:resolve_pid, _} ->
            assert result == {:resolved, hd(args)}

          {:generate_id, 0} ->
            assert result == "generated_id_12345"

          {:log_level, 2} ->
            assert result == {:log, hd(args), List.last(args)}
        end
      end)
    end
  end

  describe "discovery delegations" do
    test "all discovery functions delegate properly" do
      stub(Jido.Discovery, :list_actions, fn opts -> {:actions, opts} end)
      stub(Jido.Discovery, :list_sensors, fn opts -> {:sensors, opts} end)
      stub(Jido.Discovery, :list_agents, fn opts -> {:agents, opts} end)
      stub(Jido.Discovery, :list_skills, fn opts -> {:skills, opts} end)
      stub(Jido.Discovery, :list_demos, fn opts -> {:demos, opts} end)
      stub(Jido.Discovery, :get_action_by_slug, fn slug -> {:action, slug} end)
      stub(Jido.Discovery, :get_sensor_by_slug, fn slug -> {:sensor, slug} end)
      stub(Jido.Discovery, :get_agent_by_slug, fn slug -> {:agent, slug} end)
      stub(Jido.Discovery, :get_skill_by_slug, fn slug -> {:skill, slug} end)
      stub(Jido.Discovery, :get_demo_by_slug, fn slug -> {:demo, slug} end)

      # Test each delegation
      Enum.each(@discovery_delegations, fn {jido_func, _target_func, args, _expected_call} ->
        result = apply(Jido, jido_func, args)

        case jido_func do
          :list_actions ->
            expected = if Enum.empty?(args), do: [], else: hd(args)
            assert result == {:actions, expected}

          :list_sensors ->
            expected = if Enum.empty?(args), do: [], else: hd(args)
            assert result == {:sensors, expected}

          :list_agents ->
            expected = if Enum.empty?(args), do: [], else: hd(args)
            assert result == {:agents, expected}

          :list_skills ->
            expected = if Enum.empty?(args), do: [], else: hd(args)
            assert result == {:skills, expected}

          :list_demos ->
            expected = if Enum.empty?(args), do: [], else: hd(args)
            assert result == {:demos, expected}

          :get_action_by_slug ->
            assert result == {:action, hd(args)}

          :get_sensor_by_slug ->
            assert result == {:sensor, hd(args)}

          :get_agent_by_slug ->
            assert result == {:agent, hd(args)}

          :get_skill_by_slug ->
            assert result == {:skill, hd(args)}

          :get_demo_by_slug ->
            assert result == {:demo, hd(args)}
        end
      end)
    end
  end

  describe "module structure and compilation" do
    test "module compiles correctly with all delegates" do
      assert function_exported?(Jido, :start_agent, 1)
      assert function_exported?(Jido, :start_agent, 2)
      assert function_exported?(Jido, :ensure_started, 1)
      assert function_exported?(Jido, :list_actions, 0)
      assert function_exported?(Jido, :list_actions, 1)
      assert function_exported?(Jido, :via, 1)
      assert function_exported?(Jido, :via, 2)
      assert Code.ensure_loaded?(Jido)
    end

    test "TestJido integration - module is properly created with use Jido" do
      assert function_exported?(TestJido, :config, 0)
      assert function_exported?(TestJido, :start_link, 0)
      assert function_exported?(TestJido, :child_spec, 1)
    end
  end
end
