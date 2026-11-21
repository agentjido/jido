defmodule Jido.BehaviorTree.Error do
  @moduledoc """
  Centralized error handling for Jido BehaviorTree using Splode.

  Provides two error classes:
  - `:invalid` - Validation and configuration errors
  - `:execution` - Runtime execution errors
  """
  use Splode,
    error_classes: [
      invalid: Invalid,
      execution: Execution
    ],
    unknown_error: Splode.Error.Unknown

  defmodule Invalid do
    @moduledoc "Invalid input/config error class"
    use Splode.ErrorClass, class: :invalid
  end

  defmodule Execution do
    @moduledoc "Execution error class"
    use Splode.ErrorClass, class: :execution
  end

  defmodule BehaviorTreeError do
    @moduledoc "General behavior tree error"
    use Splode.Error,
      fields: [
        message: "Behavior tree error",
        details: %{}
      ],
      class: :execution

    @type t :: %__MODULE__{
            message: String.t(),
            details: map(),
            class: :invalid | :execution
          }
  end

  @doc "Creates a validation error with the given message and optional details."
  @spec validation_error(String.t(), map()) :: BehaviorTreeError.t()
  def validation_error(message, details \\ %{}) when is_map(details) do
    build_error(message, Map.put(details, :type, :validation), :invalid)
  end

  @doc "Creates an execution error with the given message and optional details."
  @spec execution_error(String.t(), map()) :: BehaviorTreeError.t()
  def execution_error(message, details \\ %{}) when is_map(details) do
    build_error(message, Map.put(details, :type, :execution), :execution)
  end

  @doc "Creates a node-specific error with the given message, node module, and optional details."
  @spec node_error(String.t(), module(), map()) :: BehaviorTreeError.t()
  def node_error(message, node_module, details \\ %{}) when is_map(details) do
    build_error(message, Map.merge(details, %{type: :node, node: node_module}), :execution)
  end

  defp build_error(message, details, class) do
    BehaviorTreeError.exception(
      message: message,
      details: details,
      class: class,
      splode: __MODULE__
    )
  end
end
