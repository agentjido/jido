defmodule Jido.Igniter.Templates do
  @moduledoc false
  # Template generators for Jido Igniter mix tasks

  @doc """
  Returns the template for an Agent module.
  """
  @spec agent_template(module :: String.t(), name :: String.t()) :: String.t()
  def agent_template(module, name) do
    """
    defmodule #{module} do
      use Jido.Agent,
        name: "#{name}",
        description: "TODO: Add description",
        schema: []
    end
    """
  end

  @doc """
  Returns the template for an Agent test module.
  """
  @spec agent_test_template(module :: String.t(), test_module :: String.t()) :: String.t()
  def agent_test_template(module, test_module) do
    """
    defmodule #{test_module} do
      use ExUnit.Case, async: true

      alias #{module}

      describe "new/1" do
        test "creates agent with default state" do
          agent = #{module |> String.split(".") |> List.last()}.new()
          assert agent.name == #{module |> String.split(".") |> List.last()}.name()
        end

        test "creates agent with custom id" do
          agent = #{module |> String.split(".") |> List.last()}.new(id: "custom-id")
          assert agent.id == "custom-id"
        end
      end
    end
    """
  end

  @doc """
  Returns the template for a Plugin module.
  """
  @spec plugin_template(
          module :: String.t(),
          name :: String.t(),
          state_key :: String.t(),
          signal_patterns :: [String.t()]
        ) :: String.t()
  def plugin_template(module, name, state_key, signal_patterns) do
    patterns_str = Enum.map_join(signal_patterns, ", ", &~s("#{&1}"))

    """
    defmodule #{module} do
      use Jido.Plugin,
        name: "#{name}",
        state_key: :#{state_key},
        actions: [],
        schema: Zoi.object(%{}),
        signal_patterns: [#{patterns_str}]

      @impl Jido.Plugin
      def signal_routes(_config) do
        []
      end
    end
    """
  end

  @doc """
  Returns the template for a Plugin test module.
  """
  @spec plugin_test_template(module :: String.t(), test_module :: String.t()) :: String.t()
  def plugin_test_template(module, test_module) do
    alias_name = module |> String.split(".") |> List.last()

    """
    defmodule #{test_module} do
      use ExUnit.Case, async: true

      alias #{module}

      describe "plugin_spec/1" do
        test "returns plugin specification" do
          spec = #{alias_name}.plugin_spec(%{})
          assert spec.module == #{alias_name}
          assert spec.name == #{alias_name}.name()
        end
      end

      describe "mount/2" do
        test "returns default state" do
          assert {:ok, %{}} = #{alias_name}.mount(nil, %{})
        end
      end
    end
    """
  end

  @doc """
  Returns the template for a Sensor module.
  """
  @spec sensor_template(module :: String.t(), name :: String.t(), interval :: pos_integer()) ::
          String.t()
  def sensor_template(module, name, interval) do
    """
    defmodule #{module} do
      use Jido.Sensor,
        name: "#{name}",
        description: "TODO: Add description",
        schema: Zoi.object(%{
          interval: Zoi.integer() |> Zoi.default(#{interval})
        })

      @impl true
      def init(config, _context) do
        {:ok, %{interval: config[:interval] || #{interval}}, [{:schedule, config[:interval] || #{interval}}]}
      end

      @impl true
      def handle_event(:poll, state) do
        # TODO: Implement polling logic
        {:ok, state, []}
      end
    end
    """
  end

  @doc """
  Returns the template for a Sensor test module.
  """
  @spec sensor_test_template(module :: String.t(), test_module :: String.t()) :: String.t()
  def sensor_test_template(module, test_module) do
    alias_name = module |> String.split(".") |> List.last()

    """
    defmodule #{test_module} do
      use ExUnit.Case, async: true

      alias #{module}

      describe "init/2" do
        test "initializes with default interval" do
          assert {:ok, state, directives} = #{alias_name}.init(%{}, %{})
          assert is_map(state)
          assert is_list(directives)
        end
      end

      describe "handle_event/2" do
        test "handles poll event" do
          {:ok, state, _} = #{alias_name}.init(%{}, %{})
          assert {:ok, _state, signals} = #{alias_name}.handle_event(:poll, state)
          assert is_list(signals)
        end
      end
    end
    """
  end
end
