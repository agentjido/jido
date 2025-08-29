defmodule Jido.Agent.Utilities do
  @moduledoc """
  Utility functions for Jido agents.

  This module provides common utility functions used across the Jido agent system:

  - `via/2` - Creates via tuples for OTP process registration
  - `resolve_pid/1` - Resolves various server references to PIDs  
  - `generate_id/0` - Generates UUID-v7 strings for agent IDs
  - `log_level/2` - Dynamically changes log level for running agents

  These functions support the core agent lifecycle and interaction patterns
  in Jido, providing consistent utilities for agent management and communication.

  ## Examples

      # Create via tuple for agent registration
      via_tuple = Jido.Agent.Utilities.via("worker-1")

      # Resolve agent reference to PID
      {:ok, pid} = Jido.Agent.Utilities.resolve_pid("worker-1")

      # Generate new agent ID
      id = Jido.Agent.Utilities.generate_id()

      # Update agent log level
      :ok = Jido.Agent.Utilities.log_level("worker-1", :debug)
  """

  @type agent_id :: String.t() | atom()
  @type agent_ref :: pid() | {:ok, pid()} | agent_id()
  @type registry :: module()
  @type server ::
          pid() | atom() | binary() | {name :: atom() | binary(), registry :: module()}

  # ============================================================================
  # Registry / PID Resolution Helpers
  # ============================================================================

  @doc """
  Creates a via tuple for OTP process registration.

  Returns a `{:via, Registry, {registry, id}}` tuple that can be used in
  GenServer names and other OTP registration contexts.

  ## Parameters

  - `id`: Agent ID string or atom
  - `opts`: Optional keyword list:
    - `:registry` - Registry module (defaults to `Jido.Registry`)

  ## Returns

  - `{:via, Registry, {registry_module, id}}` tuple

  ## Examples

      # Basic via tuple
      via_tuple = Jido.Agent.Utilities.via("worker-1")
      # => {:via, Registry, {Jido.Registry, "worker-1"}}

      # Custom registry
      via_tuple = Jido.Agent.Utilities.via("worker-1", registry: MyApp.Registry)
      # => {:via, Registry, {MyApp.Registry, "worker-1"}}

      # Use in GenServer.start_link
      GenServer.start_link(MyWorker, [], name: Jido.Agent.Utilities.via("worker-1"))

      # Pattern matching
      {:via, Registry, {registry, id}} = Jido.Agent.Utilities.via("worker-1")
  """
  @spec via(agent_id(), keyword()) :: {:via, Registry, {registry(), agent_id()}}
  def via(id, opts \\ []) when is_binary(id) or is_atom(id) do
    registry = opts[:registry] || Jido.Registry
    {:via, Registry, {registry, id}}
  end

  @doc """
  Resolves various server references to PIDs.

  Handles PID passthrough, registry lookups, and atom/binary name resolution.

  ## Parameters

  - `server`: PID, atom name, binary name, or `{name, registry}` tuple

  ## Returns

  - `{:ok, pid}` - Successfully resolved to PID
  - `{:error, :server_not_found}` - Could not find server

  ## Examples

      # PID passthrough
      {:ok, pid} = Jido.Agent.Utilities.resolve_pid(self())

      # Registry lookup
      {:ok, pid} = Jido.Agent.Utilities.resolve_pid("worker-1")

      # Custom registry
      {:ok, pid} = Jido.Agent.Utilities.resolve_pid({"worker-1", MyApp.Registry})
  """
  @spec resolve_pid(server()) :: {:ok, pid()} | {:error, :server_not_found}
  def resolve_pid(pid) when is_pid(pid), do: {:ok, pid}

  def resolve_pid({name, registry})
      when (is_atom(name) or is_binary(name)) and is_atom(registry) do
    name = if is_atom(name), do: Atom.to_string(name), else: name

    case Registry.lookup(registry, name) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :server_not_found}
    end
  end

  def resolve_pid(name) when is_atom(name) or is_binary(name) do
    name = if is_atom(name), do: Atom.to_string(name), else: name
    resolve_pid({name, Jido.Registry})
  end

  # ============================================================================
  # Utility Functions
  # ============================================================================

  @doc """
  Generates a new UUID-v7 string for use as agent IDs.

  Returns a time-ordered UUID that provides both uniqueness and rough
  chronological ordering. Same algorithm used internally when agents
  are started without explicit IDs.

  ## Returns

  - UUID-v7 string in standard format

  ## Examples

      # Generate new agent ID
      id = Jido.Agent.Utilities.generate_id()
      # => "01234567-89ab-cdef-0123-456789abcdef"

      # Use in agent creation
      {:ok, pid} = Jido.start_agent(MyApp.WorkerAgent, id: Jido.Agent.Utilities.generate_id())

      # Generate multiple IDs
      ids = for _ <- 1..5, do: Jido.Agent.Utilities.generate_id()
  """
  @spec generate_id() :: String.t()
  def generate_id do
    Jido.Signal.ID.generate!()
  end

  @doc """
  Dynamically changes the log level for a running agent.

  Sends a cast signal to modify the agent's logging configuration at runtime.
  Useful for debugging and troubleshooting without restarting agents.

  ## Parameters

  - `agent_ref`: Agent PID, ID, or `{:ok, pid}` tuple
  - `level`: New log level atom (`:debug`, `:info`, `:warn`, `:error`)

  ## Returns

  - `:ok` - Log level updated successfully
  - `{:error, reason}` - Failed to update log level

  ## Examples

      # Enable debug logging
      :ok = Jido.Agent.Utilities.log_level("worker-1", :debug)

      # Reduce logging to errors only
      :ok = Jido.Agent.Utilities.log_level("worker-1", :error)

      # Pipe-friendly usage
      "worker-1" |> Jido.get_agent() |> elem(1) |> Jido.Agent.Utilities.log_level(:info)

      # Update multiple agents
      for id <- ["worker-1", "worker-2", "worker-3"] do
        Jido.Agent.Utilities.log_level(id, :warn)
      end
  """
  @spec log_level(agent_ref(), atom()) :: :ok | {:error, term()}
  def log_level(_agent_ref, level) when level not in [:debug, :info, :warn, :error] do
    {:error, {:invalid_log_level, level}}
  end

  def log_level(agent_ref, level) when level in [:debug, :info, :warn, :error] do
    log_level_impl(agent_ref, level)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  @spec log_level_impl(agent_ref(), atom()) :: :ok | {:error, term()}
  defp log_level_impl({:ok, pid}, level), do: log_level_impl(pid, level)

  defp log_level_impl(pid, level) when is_pid(pid) do
    # Build a signal to update the agent's log level
    with {:ok, signal} <-
           Jido.Signal.new(%{
             type: "agent.config.update",
             source: "/jido/utilities",
             data: %{
               config_key: :log_level,
               config_value: level
             }
           }) do
      # Send the signal via cast to the agent
      case Jido.Agent.Server.cast(pid, signal) do
        {:ok, _signal_id} -> :ok
        error -> error
      end
    end
  end

  defp log_level_impl(id, level) when is_binary(id) or is_atom(id) do
    case Jido.Agent.Lifecycle.get_agent(id) do
      {:ok, pid} -> log_level_impl(pid, level)
      error -> error
    end
  end
end
