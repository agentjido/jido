defmodule Jido.Util do
  @moduledoc """
  A collection of utility functions for the Jido framework.

  This module provides various helper functions that are used throughout the Jido framework,
  including:

  - ID generation
  - Name validation
  - Error handling
  - Logging utilities

  These utilities are designed to support common operations and maintain consistency
  across the Jido ecosystem. They encapsulate frequently used patterns and provide
  a centralized location for shared functionality.

  Many of the functions in this module are used internally by other Jido modules,
  but they can also be useful for developers building applications with Jido.
  """

  alias Jido.Error

  require OK

  @name_regex ~r/^[a-zA-Z][a-zA-Z0-9_]*$/

  @doc """
  Generates a unique ID.
  """
  @spec generate_id() :: String.t()
  def generate_id, do: Uniq.UUID.uuid7()

  @doc """
  Converts a string to a binary.
  """
  @spec string_to_binary!(String.t()) :: binary()
  def string_to_binary!(string) when is_binary(string) do
    string
  end

  @doc """
  Validates the name of a Action.

  The name must contain only letters, numbers, and underscores.

  ## Parameters

  - `name`: The name to validate.

  ## Returns

  - `{:ok, name}` if the name is valid.
  - `{:error, reason}` if the name is invalid.

  ## Examples

      iex> Jido.Action.validate_name("valid_name_123")
      {:ok, "valid_name_123"}

      iex> Jido.Action.validate_name("invalid-name")
      {:error, "The name must contain only letters, numbers, and underscores."}

  """
  @spec validate_name(any()) :: {:ok, String.t()} | {:error, Error.t()}
  def validate_name(name) when is_binary(name) do
    if Regex.match?(@name_regex, name) do
      OK.success(name)
    else
      "The name must start with a letter and contain only letters, numbers, and underscores."
      |> OK.failure()
    end
  end

  def validate_name(_) do
    "Invalid name format."
    |> OK.failure()
  end

  @doc """
  Validates that all modules in a list implement the Jido.Action behavior.
  Used as a custom validator for NimbleOptions.

  This function ensures that all provided modules are valid Jido.Action implementations
  by checking that they:
  1. Are valid Elixir modules that can be loaded
  2. Export the required __action_metadata__/0 function that indicates Jido.Action behavior

  ## Parameters

  - `actions`: A list of module atoms or a single module atom to validate

  ## Returns

  - `{:ok, actions}` if all modules are valid Jido.Action implementations
  - `{:error, reason}` if any module is invalid

  ## Examples

      iex> defmodule ValidAction do
      ...>   use Jido.Action,
      ...>     name: "valid_action"
      ...> end
      ...> Jido.Util.validate_actions([ValidAction])
      {:ok, [ValidAction]}

      iex> Jido.Util.validate_actions([InvalidModule])
      {:error, "All actions must implement the Jido.Action behavior"}

      # Single module validation
      iex> Jido.Util.validate_actions(ValidAction)
      {:ok, [ValidAction]}
  """
  @spec validate_actions(list(module()) | module()) ::
          {:ok, list(module())} | {:error, String.t()}
  def validate_actions(actions) when is_list(actions) do
    if Enum.all?(actions, &implements_action?/1) do
      {:ok, actions}
    else
      {:error, "All actions must implement the Jido.Action behavior"}
    end
  end

  def validate_actions(action) when is_atom(action) do
    validate_actions([action])
  end

  defp implements_action?(module) when is_atom(module) do
    Code.ensure_loaded?(module) && function_exported?(module, :__action_metadata__, 0)
  end

  @doc """
  Validates that a module implements the Jido.Runner behavior.

  This function ensures that the provided module is a valid Jido.Runner implementation
  by checking that it:
  1. Is a valid Elixir module that can be loaded
  2. Exports the required run/2 function that indicates Jido.Runner behavior

  ## Parameters

  - `module`: The module atom to validate

  ## Returns

  - `{:ok, module}` if the module is a valid Jido.Runner implementation
  - `{:error, Jido.Error.t()}` if the module is invalid

  ## Examples

      iex> defmodule ValidRunner do
      ...>   @behaviour Jido.Runner
      ...>   def run(agent, opts), do: {:ok, agent}
      ...> end
      ...> Jido.Util.validate_runner(ValidRunner)
      {:ok, ValidRunner}

      iex> Jido.Util.validate_runner(InvalidModule)
      {:error, %Jido.Error{type: :validation_error, message: "Module InvalidModule must implement run/2"}}
  """
  @spec validate_runner(module()) :: {:ok, module()} | {:error, Jido.Error.t()}
  def validate_runner(module) when is_atom(module) do
    with true <- Code.ensure_loaded?(module),
         true <- function_exported?(module, :run, 2) do
      {:ok, module}
    else
      false ->
        {:error,
         Jido.Error.validation_error(
           "Runner module #{inspect(module)} must exist and implement run/2",
           %{
             module: module
           }
         )}
    end
  end

  @doc false
  def pluck(enumerable, field) do
    Enum.map(enumerable, &Map.get(&1, field))
  end
end
