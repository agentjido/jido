defmodule Jido.Skills.Arithmetic do
  @moduledoc """
  Provides basic arithmetic operations as a Skill.

  This skill exposes arithmetic operations like addition, subtraction, multiplication,
  division and squaring through a signal-based interface.
  """
  use Jido.Skill,
    name: "arithmetic",
    description: "Provides basic arithmetic operations",
    category: "math",
    tags: ["math", "arithmetic", "calculations"],
    vsn: "1.0.0",
    opts_key: :arithmetic,
    opts_schema: [
      max_value: [
        type: :integer,
        required: false,
        default: 1_000_000,
        doc: "Maximum allowed value for calculations"
      ]
    ],
    signal_patterns: [
      "arithmetic.*"
    ]

  alias Jido.Signal
  alias Jido.Instruction

  defmodule Actions do
    @moduledoc false
    defmodule Add do
      @moduledoc false
      use Jido.Action,
        name: "add",
        description: "Adds two numbers",
        schema: [
          value: [type: :number, required: true, doc: "The first number to add"],
          amount: [type: :number, required: true, doc: "The second number to add"]
        ]

      def run(%{value: value, amount: amount}, _context) do
        {:ok, %{result: value + amount}}
      end
    end

    defmodule Subtract do
      @moduledoc false
      use Jido.Action,
        name: "subtract",
        description: "Subtracts one number from another",
        schema: [
          value: [type: :number, required: true, doc: "The number to subtract from"],
          amount: [type: :number, required: true, doc: "The number to subtract"]
        ]

      def run(%{value: value, amount: amount}, _context) do
        {:ok, %{result: value - amount}}
      end
    end

    defmodule Multiply do
      @moduledoc false
      use Jido.Action,
        name: "multiply",
        description: "Multiplies two numbers",
        schema: [
          value: [type: :number, required: true, doc: "The first number to multiply"],
          amount: [type: :number, required: true, doc: "The second number to multiply"]
        ]

      def run(%{value: value, amount: amount}, _context) do
        {:ok, %{result: value * amount}}
      end
    end

    defmodule Divide do
      @moduledoc false
      use Jido.Action,
        name: "divide",
        description: "Divides one number by another",
        schema: [
          value: [type: :number, required: true, doc: "The number to be divided (dividend)"],
          amount: [type: :number, required: true, doc: "The number to divide by (divisor)"]
        ]

      def run(%{value: _value, amount: 0}, _context) do
        {:error, "Cannot divide by zero"}
      end

      def run(%{value: value, amount: amount}, _context) do
        {:ok, %{result: value / amount}}
      end
    end

    defmodule Square do
      @moduledoc false
      use Jido.Action,
        name: "square",
        description: "Squares a number",
        schema: [
          value: [type: :number, required: true, doc: "The number to be squared"]
        ]

      def run(%{value: value}, _context) do
        {:ok, %{result: value * value}}
      end
    end

    defmodule Eval do
      @moduledoc false
      use Jido.Action,
        name: "eval",
        description: "Evaluates a mathematical expression",
        schema: [
          expression: [
            type: :string,
            required: true,
            doc: "The mathematical expression to evaluate"
          ]
        ]

      @doc """
      Performs the calculation specified in the expression and returns the response
      to be used by the the LLM.
      """
      @spec run(args :: %{String.t() => any()}, context :: map()) ::
              {:ok, map()} | {:error, String.t()}
      def run(%{expression: expr}, _context) do
        try do
          case Abacus.eval(expr) do
            {:ok, number} ->
              {:ok, %{result: number}}

            {:error, reason} ->
              {:error,
               "ERROR: #{inspect(expr)} is not a valid expression, Reason: #{inspect(reason)}"}
          end
        rescue
          err ->
            {:error, "ERROR: An invalid expression raised the exception #{inspect(err)}"}
        end
      end
    end
  end

  @doc """
  Skill: Arithmetic
  Signal Contracts:
  - Incoming:
    * arithmetic.add: Add two numbers
    * arithmetic.subtract: Subtract two numbers
    * arithmetic.multiply: Multiply two numbers
    * arithmetic.divide: Divide two numbers
    * arithmetic.square: Square a number
    * arithmetic.eval: Evaluate a mathematical expression
  - Outgoing:
    * arithmetic.result: Result of arithmetic operation
    * arithmetic.error: Error from arithmetic operation
  """
  @impl true
  @spec router(keyword()) :: [Jido.Signal.Router.Route.t()]
  def router(_opts) do
    [
      %Jido.Signal.Router.Route{
        path: "arithmetic.add",
        target: %Instruction{action: Actions.Add},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "arithmetic.subtract",
        target: %Instruction{action: Actions.Subtract},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "arithmetic.multiply",
        target: %Instruction{action: Actions.Multiply},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "arithmetic.divide",
        target: %Instruction{action: Actions.Divide},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "arithmetic.square",
        target: %Instruction{action: Actions.Square},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "arithmetic.eval",
        target: %Instruction{action: Actions.Eval},
        priority: 0
      }
    ]
  end

  @doc """
  Handle an arithmetic signal.
  """
  @impl true
  @spec handle_signal(Signal.t(), Jido.Skill.t()) :: {:ok, Signal.t()}
  def handle_signal(%Signal{} = signal, _skill) do
    operation = signal.type |> String.split(".") |> List.last() |> String.to_atom()
    {:ok, %{signal | data: Map.put(signal.data, :operation, operation)}}
  end

  @doc """
  Process the result of an arithmetic operation.
  """
  @impl true
  @spec transform_result(Signal.t(), {:ok, map()} | {:error, String.t()}, Jido.Skill.t()) ::
          {:ok, Signal.t()}
  def transform_result(%Signal{} = signal, {:ok, result}, _skill) do
    operation = signal.type |> String.split(".") |> List.last() |> String.to_atom()

    {:ok,
     %Signal{
       id: Jido.Util.generate_id(),
       source: signal.source,
       type: "arithmetic.result",
       data: Map.merge(result, %{operation: operation})
     }}
  end

  def transform_result(%Signal{} = signal, {:error, error}, _skill) do
    operation = signal.type |> String.split(".") |> List.last() |> String.to_atom()

    {:ok,
     %Signal{
       id: Jido.Util.generate_id(),
       source: signal.source,
       type: "arithmetic.error",
       data: %{
         error: error,
         operation: operation
       }
     }}
  end
end
