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
    schema_key: :arithmetic,
    signals: %{
      input: [
        "arithmetic.add",
        "arithmetic.subtract",
        "arithmetic.multiply",
        "arithmetic.divide",
        "arithmetic.square",
        "arithmetic.eval"
      ],
      output: [
        "arithmetic.result",
        "arithmetic.error"
      ]
    },
    config: %{
      max_value: [
        type: :integer,
        required: false,
        default: 1_000_000,
        doc: "Maximum allowed value for calculations"
      ]
    }

  defmodule Actions do
    defmodule Add do
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
  def router do
    [
      %{
        path: "arithmetic.add",
        instruction: %{
          action: Actions.Add
        }
      },
      %{
        path: "arithmetic.subtract",
        instruction: %{
          action: Actions.Subtract
        }
      },
      %{
        path: "arithmetic.multiply",
        instruction: %{
          action: Actions.Multiply
        }
      },
      %{
        path: "arithmetic.divide",
        instruction: %{
          action: Actions.Divide
        }
      },
      %{
        path: "arithmetic.square",
        instruction: %{
          action: Actions.Square
        }
      },
      %{
        path: "arithmetic.eval",
        instruction: %{
          action: Actions.Eval
        }
      }
    ]
  end

  def initial_state do
    %{
      last_result: nil,
      operation_count: %{
        add: 0,
        subtract: 0,
        multiply: 0,
        divide: 0,
        square: 0,
        eval: 0
      }
    }
  end

  def handle_result(%Result{status: :ok} = result, path) do
    operation = path |> String.split(".") |> List.last() |> String.to_atom()

    [
      %Signal{
        id: UUID.uuid4(),
        source: "replace_agent_id",
        type: "arithmetic.result",
        data: Map.merge(result.result_state, %{operation: operation})
      }
    ]
  end

  def handle_result(%Result{status: :error} = result, path) do
    operation = path |> String.split(".") |> List.last() |> String.to_atom()

    [
      %Signal{
        id: UUID.uuid4(),
        source: "replace_agent_id",
        type: "arithmetic.error",
        data: %{
          error: result.error,
          operation: operation
        }
      }
    ]
  end
end
