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
  require Logger

  @name_regex ~r/^[a-zA-Z][a-zA-Z0-9_]*$/

  @doc """
  Generates a unique ID.
  """
  @spec generate_id() :: String.t()
  def generate_id, do: Jido.Signal.ID.generate!()

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
          {:ok, list(module()) | module()} | {:error, String.t()}
  def validate_actions(actions) when is_list(actions) do
    if Enum.all?(actions, &implements_action?/1) do
      {:ok, actions}
    else
      {:error, "All actions must implement the Jido.Action behavior"}
    end
  end

  def validate_actions(action) when is_atom(action) do
    if implements_action?(action) do
      {:ok, action}
    else
      {:error, "All actions must implement the Jido.Action behavior"}
    end
  end

  defp implements_action?(module) when is_atom(module) do
    Code.ensure_loaded?(module) && function_exported?(module, :__action_metadata__, 0)
  end

  @doc """
  Validates that a module is a valid Elixir module that can be loaded.
  Used as a custom validator for NimbleOptions.

  ## Parameters

  - `module`: A module atom to validate

  ## Returns

  - `{:ok, module}` if the module is valid
  - `{:error, reason}` if the module is invalid

  ## Examples

      iex> Jido.Util.validate_module(Enum)
      {:ok, Enum}

      iex> Jido.Util.validate_module(:invalid_module)
      {:error, "Module :invalid_module does not exist or cannot be loaded"}
  """
  @spec validate_module(any()) :: {:ok, module()} | {:error, String.t()}
  def validate_module(module) when is_atom(module) do
    if Code.ensure_loaded?(module) do
      {:ok, module}
    else
      {:error, "Module #{inspect(module)} does not exist or cannot be loaded"}
    end
  end

  def validate_module(_) do
    {:error, "Module must be an atom"}
  end

  @doc """
  Validates that a module is a valid Elixir module that can be compiled.
  Used as a custom validator for NimbleOptions that handles compilation order.

  Uses Code.ensure_compiled/1 which blocks until the module finishes compilation
  or returns an error, making it safe for parallel compilation scenarios.

  ## Parameters

  - `module` - The module atom to validate

  ## Returns

  - `{:ok, module}` if the module can be compiled
  - `{:error, reason}` if the module is invalid or cannot be compiled

  ## Examples

      iex> Jido.Util.validate_module_compiled(Enum)
      {:ok, Enum}

      iex> Jido.Util.validate_module_compiled(:invalid_module)
      {:error, "Module :invalid_module does not exist or could not be compiled"}
  """
  @spec validate_module_compiled(any()) :: {:ok, module()} | {:error, String.t()}
  def validate_module_compiled(module) when is_atom(module) do
    case Code.ensure_compiled(module) do
      {:module, _} ->
        {:ok, module}

      {:error, _reason} ->
        {:error, "Module #{inspect(module)} does not exist or could not be compiled"}
    end
  end

  def validate_module_compiled(_) do
    {:error, "Module must be an atom"}
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
      {:error, %Jido.Error.InvalidInputError{message: "Runner module InvalidModule must exist and implement run/2"}}
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

  @type server :: pid() | atom() | binary() | {name :: atom() | binary(), registry :: module()}

  @doc """
  Creates a via tuple for process registration with a registry.

  ## Parameters

  - name: The name to register (atom, string, or {name, registry} tuple)
  - opts: Options list
    - :registry - The registry module to use (defaults to Jido.Registry)

  ## Returns

  A via tuple for use with process registration

  ## Examples

      iex> Jido.Util.via_tuple(:my_process)
      {:via, Registry, {Jido.Registry, "my_process"}}

      iex> Jido.Util.via_tuple(:my_process, registry: MyRegistry)
      {:via, Registry, {MyRegistry, "my_process"}}

      iex> Jido.Util.via_tuple({:my_process, MyRegistry})
      {:via, Registry, {MyRegistry, "my_process"}}
  """
  @spec via_tuple(server(), keyword()) :: {:via, Registry, {module(), String.t()}}
  def via_tuple(name_or_tuple, opts \\ [])

  def via_tuple({name, registry}, _opts) when is_atom(registry) do
    name = if is_atom(name), do: Atom.to_string(name), else: name
    {:via, Registry, {registry, name}}
  end

  def via_tuple(name, opts) do
    registry = Keyword.get(opts, :registry, Jido.Registry)
    name = if is_atom(name), do: Atom.to_string(name), else: name
    {:via, Registry, {registry, name}}
  end

  @doc """
  Finds a process by name, pid, or {name, registry} tuple.

  ## Parameters

  - server: The process identifier (pid, name, or {name, registry} tuple)
  - opts: Options list
    - :registry - The registry module to use (defaults to Jido.Registry)

  ## Returns

  - `{:ok, pid}` if process is found
  - `{:error, :not_found}` if process is not found

  ## Examples

      iex> Jido.Util.whereis(pid)
      {:ok, #PID<0.123.0>}

      iex> Jido.Util.whereis(:my_process)
      {:ok, #PID<0.124.0>}

      iex> Jido.Util.whereis({:my_process, MyRegistry})
      {:ok, #PID<0.125.0>}
  """
  @spec whereis(server(), keyword()) :: {:ok, pid()} | {:error, :not_found}
  def whereis(server, opts \\ [])

  def whereis(pid, _opts) when is_pid(pid), do: {:ok, pid}

  def whereis({name, registry}, _opts) when is_atom(registry) do
    name = if is_atom(name), do: Atom.to_string(name), else: name

    case Registry.lookup(registry, name) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  def whereis(name, opts) do
    registry = Keyword.get(opts, :registry, Jido.Registry)
    name = if is_atom(name), do: Atom.to_string(name), else: name

    case Registry.lookup(registry, name) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Conditionally logs a message based on comparing threshold and message log levels.

  This function provides a way to conditionally log messages by comparing a threshold level
  against the message's intended log level. The message will only be logged if the threshold
  level is less than or equal to the message level.

  ## Parameters

  - `threshold_level`: The minimum log level threshold (e.g. :debug, :info, etc)
  - `message_level`: The log level for this specific message
  - `message`: The message to potentially log
  - `opts`: Additional options passed to Logger.log/3

  ## Returns

  - `:ok` in all cases

  ## Examples

      # Will log since :info >= :info
      iex> cond_log(:info, :info, "test message")
      :ok

      # Won't log since :info > :debug
      iex> cond_log(:info, :debug, "test message")
      :ok

      # Will log since :debug <= :info
      iex> cond_log(:debug, :info, "test message")
      :ok
  """
  def cond_log(threshold_level, message_level, message, opts \\ []) do
    valid_levels = Logger.levels()

    cond do
      threshold_level not in valid_levels or message_level not in valid_levels ->
        # Don't log
        :ok

      Logger.compare_levels(threshold_level, message_level) in [:lt, :eq] ->
        Logger.log(message_level, message, opts)

      true ->
        :ok
    end
  end
end
