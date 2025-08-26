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
    ],
    actions: [
      Jido.Tools.Arithmetic.Add,
      Jido.Tools.Arithmetic.Subtract,
      Jido.Tools.Arithmetic.Multiply,
      Jido.Tools.Arithmetic.Divide,
      Jido.Tools.Arithmetic.Square
    ]

  alias Jido.Signal
  alias Jido.Instruction

  @doc """
  Skill: Arithmetic
  Signal Contracts:
  - Incoming:
    * arithmetic.add: Add two numbers
    * arithmetic.subtract: Subtract two numbers
    * arithmetic.multiply: Multiply two numbers
    * arithmetic.divide: Divide two numbers
    * arithmetic.square: Square a number
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
        target: %Instruction{action: Jido.Tools.Arithmetic.Add},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "arithmetic.subtract",
        target: %Instruction{action: Jido.Tools.Arithmetic.Subtract},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "arithmetic.multiply",
        target: %Instruction{action: Jido.Tools.Arithmetic.Multiply},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "arithmetic.divide",
        target: %Instruction{action: Jido.Tools.Arithmetic.Divide},
        priority: 0
      },
      %Jido.Signal.Router.Route{
        path: "arithmetic.square",
        target: %Instruction{action: Jido.Tools.Arithmetic.Square},
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
