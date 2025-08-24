defmodule CalculatorAgent do
  @moduledoc """
  A simple calculator agent for performing arithmetic operations.

  CalculatorAgent provides a clean, minimal API for mathematical calculations
  while leveraging the full power of Jido.Agent.Server under the hood.

  ## Examples

      # Start a calculator agent
      {:ok, pid} = CalculatorAgent.start_link(name: "my_calculator")

      # Simple calculations
      {:ok, result} = CalculatorAgent.calculate(pid, "2 + 2")
      {:ok, result} = CalculatorAgent.calculate(pid, "sqrt(16)")

      # View calculation history
      {:ok, history} = CalculatorAgent.history(pid)
  """

  use Jido.Agent,
    name: "calculator_agent",
    description: "Simple calculator agent for arithmetic operations",
    category: "Math Agents",
    tags: ["calculator", "math", "arithmetic"],
    vsn: "1.0.0",
    schema: [
      # Track calculation history
      calculations: [type: {:list, :map}, default: []],
      calculation_count: [type: :integer, default: 0]
    ],
    actions: [
      # All actions are now automatically registered by skills
    ]

  require Logger

  @default_opts [
    agent: __MODULE__,
    mode: :auto,
    log_level: :info,
    skills: [
      Jido.Skills.Arithmetic,
      Jido.Skills.StateManager,
      Jido.Skills.BasicActions
    ]
  ]

  @default_timeout 30_000

  @impl true
  def start_link(opts) when is_list(opts) do
    # Ensure name is provided
    name = Keyword.fetch!(opts, :name)

    # Set up agent with calculation state
    initial_state = %{
      calculations: [],
      calculation_count: 0
    }

    # Set up signal routing - StateManager skill handles jido.state.* automatically
    routes = []

    # Merge default options with routing and skills
    server_opts =
      @default_opts
      |> Keyword.merge(opts)
      |> Keyword.put(:id, name)
      |> Keyword.put(:initial_state, initial_state)
      |> Keyword.put(:routes, routes)

    Jido.Agent.Server.start_link(server_opts)
  end

  @doc """
  Primary calculation interface - evaluates mathematical expressions.

  ## Examples

      {:ok, result} = CalculatorAgent.calculate(pid, "2 + 2")
      {:ok, result} = CalculatorAgent.calculate(pid, "sqrt(25) * 2")
      {:ok, result} = CalculatorAgent.calculate(pid, "sin(pi/2)")
  """
  @spec calculate(pid() | String.t(), String.t()) :: {:ok, number()} | {:error, term()}
  def calculate(agent_ref, expression) when is_binary(expression) do
    with {:ok, pid} <- resolve_pid(agent_ref),
         {:ok, signal} <- build_calc_signal(expression) do
      case Jido.Agent.Server.call(pid, signal, @default_timeout) do
        {:ok, result} ->
          # Store calculation in history
          store_calculation(pid, expression, result)
          {:ok, result}

        error ->
          error
      end
    end
  end

  @doc """
  Get the agent's calculation history.

  ## Examples

      {:ok, history} = CalculatorAgent.history(pid)
  """
  @spec history(pid() | String.t()) :: {:ok, [map()]} | {:error, term()}
  def history(agent_ref) do
    with {:ok, pid} <- resolve_pid(agent_ref),
         {:ok, state} <- Jido.Agent.Server.state(pid) do
      calculations = get_in(state.agent.state, [:calculations]) || []
      {:ok, calculations}
    end
  end

  @doc """
  Clear the agent's calculation history.

  ## Examples

      :ok = CalculatorAgent.clear(pid)
  """
  @spec clear(pid() | String.t()) :: :ok | {:error, term()}
  def clear(agent_ref) do
    with {:ok, pid} <- resolve_pid(agent_ref),
         {:ok, clear_calcs_signal} <- build_clear_calculations_signal(),
         {:ok, reset_count_signal} <- build_reset_count_signal() do
      with {:ok, _} <- Jido.Agent.Server.call(pid, clear_calcs_signal),
           {:ok, _} <- Jido.Agent.Server.call(pid, reset_count_signal) do
        :ok
      else
        error -> error
      end
    end
  end

  @doc """
  Get the count of calculations performed.

  ## Examples

      {:ok, count} = CalculatorAgent.count(pid)
  """
  @spec count(pid() | String.t()) :: {:ok, integer()} | {:error, term()}
  def count(agent_ref) do
    with {:ok, pid} <- resolve_pid(agent_ref),
         {:ok, state} <- Jido.Agent.Server.state(pid) do
      count = get_in(state.agent.state, [:calculation_count]) || 0
      {:ok, count}
    end
  end

  ## Signal Handling

  @impl true
  def transform_result(%Jido.Signal{type: "arithmetic.result"}, result, _instruction) do
    # Extract numeric result from arithmetic evaluation
    {:ok, result}
  end

  def transform_result(%Jido.Signal{type: "arithmetic.eval"}, %{result: result}, _instruction) do
    # Extract numeric result directly from Eval action
    {:ok, result}
  end

  def transform_result(%Jido.Signal{type: "jido.state.set"}, _result, _instruction) do
    {:ok, "State updated"}
  end

  def transform_result(%Jido.Signal{type: type}, result, _instruction)
      when type in ["jido.state.get", "jido.state.update", "jido.state.delete"] do
    {:ok, result}
  end

  ## Private Implementation

  defp resolve_pid(pid) when is_pid(pid), do: {:ok, pid}

  defp resolve_pid(name) when is_binary(name) do
    case Process.whereis(String.to_atom(name)) do
      nil -> {:error, {:agent_not_found, name}}
      pid -> {:ok, pid}
    end
  end

  defp build_calc_signal(expression) do
    Jido.Signal.new(%{
      type: "arithmetic.eval",
      data: %{expression: expression}
    })
  end

  defp build_clear_calculations_signal do
    Jido.Signal.new(%{
      type: "jido.state.set",
      data: %{path: [:calculations], value: []}
    })
  end

  defp build_reset_count_signal do
    Jido.Signal.new(%{
      type: "jido.state.set",
      data: %{path: [:calculation_count], value: 0}
    })
  end

  defp store_calculation(pid, expression, result) do
    # Get current state to increment count and add calculation
    with {:ok, state} <- Jido.Agent.Server.state(pid) do
      current_count = get_in(state.agent.state, [:calculation_count]) || 0
      current_calcs = get_in(state.agent.state, [:calculations]) || []

      new_calculation = %{
        expression: expression,
        result: result,
        timestamp: DateTime.utc_now()
      }

      # Update count
      count_signal =
        Jido.Signal.new!(%{
          type: "jido.state.set",
          data: %{path: [:calculation_count], value: current_count + 1}
        })

      # Update calculations list
      calc_signal =
        Jido.Signal.new!(%{
          type: "jido.state.set",
          data: %{path: [:calculations], value: [new_calculation | current_calcs]}
        })

      # Send both updates (fire and forget)
      Jido.Agent.Server.call(pid, count_signal)
      Jido.Agent.Server.call(pid, calc_signal)
    end
  end
end
