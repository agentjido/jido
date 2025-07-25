defmodule Jido.Agent.Server.Router do
  @moduledoc false

  use ExDbug, enabled: false
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Signal
  alias Jido.Signal.Router
  alias Jido.Error
  alias Jido.Instruction

  @type route_spec :: {String.t(), term()}
  @type router_opts :: [routes: [route_spec()]]

  @doc """
  Builds or updates a router with the given options.

  ## Parameters
  - state: The current server state
  - opts: Router configuration options
    - `:routes` - List of initial routes in `{event, instruction}` format

  ## Returns
  - `{:ok, updated_state}` - Router built successfully
  - `{:error, reason}` - Failed to build router

  ## Examples

      {:ok, state} = Router.build(state, routes: [
        {"user.created", CreateUserInstruction},
        {"payment.processed", ProcessPaymentInstruction}
      ])
  """
  @spec build(ServerState.t(), router_opts()) :: {:ok, ServerState.t()} | {:error, term()}
  def build(%ServerState{} = state, opts) do
    dbug("Building router", state: state, opts: opts)
    router = state.router || Signal.Router.new!()

    case opts[:routes] do
      nil ->
        dbug("No routes provided, using empty router")
        {:ok, %{state | router: router}}

      routes when is_list(routes) ->
        dbug("Adding initial routes", routes: routes)

        case Router.add(router, routes) do
          {:ok, updated_router} ->
            dbug("Router built successfully")
            {:ok, %{state | router: updated_router}}

          {:error, reason} ->
            dbug("Failed to build router", error: reason)
            {:error, reason}
        end

      invalid ->
        dbug("Invalid routes provided", routes: invalid)
        {:error, Error.validation_error("Routes must be a list", %{routes: invalid})}
    end
  end

  @doc """
  Adds one or more routes to the router.

  ## Parameters
  - state: The current server state
  - routes: Route specification(s) to add

  ## Returns
  - `{:ok, updated_state}` - Routes added successfully
  - `{:error, reason}` - Failed to add routes

  ## Examples

      {:ok, state} = Router.add(state, {"metrics.collected", CollectMetricsInstruction})
      {:ok, state} = Router.add(state, [
        {"user.created", CreateUserInstruction},
        {"user.updated", UpdateUserInstruction}
      ])
  """
  @spec add(ServerState.t(), route_spec() | [route_spec()]) ::
          {:ok, ServerState.t()} | {:error, term()}
  def add(%ServerState{} = state, routes) do
    dbug("Adding routes", state: state, routes: routes)

    case Signal.Router.add(state.router, routes) do
      {:ok, updated_router} ->
        dbug("Routes added successfully")
        {:ok, %{state | router: updated_router}}

      error ->
        dbug("Failed to add routes", error: error)
        error
    end
  end

  @doc """
  Removes one or more routes from the router.

  ## Parameters
  - state: The current server state
  - paths: Path string or list of path strings to remove

  ## Returns
  - `{:ok, updated_state}` - Routes removed successfully

  ## Examples

      {:ok, state} = Router.remove(state, "metrics.collected")
      {:ok, state} = Router.remove(state, ["user.created", "user.updated"])
  """
  @spec remove(ServerState.t(), String.t() | [String.t()]) :: {:ok, ServerState.t()}
  def remove(%ServerState{} = state, paths) when is_list(paths) do
    dbug("Removing routes", state: state, paths: paths)
    {:ok, updated_router} = Signal.Router.remove(state.router, paths)
    dbug("Routes removed successfully")
    {:ok, %{state | router: updated_router}}
  end

  def remove(%ServerState{} = state, path) when is_binary(path) do
    dbug("Removing single route", state: state, path: path)
    remove(state, [path])
  end

  @doc """
  Lists all routes currently configured in the router.

  ## Parameters
  - state: The current server state

  ## Returns
  - `{:ok, routes}` where routes is a list of Route structs

  ## Examples

      {:ok, routes} = Router.list(state)
      Enum.each(routes, fn route ->
        IO.puts("\#{route.path} -> \#{inspect(route.instruction)}")
      end)
  """
  @spec list(ServerState.t()) :: {:ok, [Signal.Router.Route.t()]} | {:error, term()}
  def list(%ServerState{} = state) do
    dbug("Listing routes", state: state)
    Signal.Router.list(state.router)
  end

  @doc """
  Merges routes from another router or list of routes into this one.

  ## Parameters
  - state: The current server state
  - routes: One of:
    - A list of Route structs
    - Another router struct

  ## Returns
  - `{:ok, updated_state}` - Successfully merged routes
  - `{:error, reason}` - Failed to merge routes

  ## Examples

      # Merge from route list
      {:ok, state} = Router.merge(state, other_routes)

      # Merge from another router
      {:ok, state} = Router.merge(state, other_router)
  """
  @spec merge(ServerState.t(), [Signal.Router.Route.t()] | Signal.Router.Router.t()) ::
          {:ok, ServerState.t()} | {:error, term()}
  def merge(%ServerState{} = state, routes) when is_list(routes) do
    dbug("Merging route list", state: state, routes: routes)

    case Signal.Router.merge(state.router, routes) do
      {:ok, updated_router} ->
        dbug("Routes merged successfully")
        {:ok, %{state | router: updated_router}}

      {:error, reason} ->
        dbug("Failed to merge routes", error: reason)
        {:error, reason}
    end
  end

  def merge(%ServerState{} = state, %Router.Router{} = other_router) do
    dbug("Merging router", state: state, other_router: other_router)

    with {:ok, routes} <- Signal.Router.list(other_router),
         {:ok, updated_router} <- Signal.Router.merge(state.router, routes) do
      dbug("Router merged successfully")
      {:ok, %{state | router: updated_router}}
    else
      {:error, reason} ->
        dbug("Failed to merge router", error: reason)
        {:error, reason}
    end
  end

  def merge(%ServerState{} = _state, invalid) do
    dbug("Invalid merge input", invalid: invalid)
    {:error, Error.validation_error("Invalid routes for merging", %{routes: invalid})}
  end

  @doc """
  Routes a signal through the router to get matching instructions.

  ## Parameters
  - state: The current server state
  - signal: The signal to route

  If the signal.data contains a single Instruction struct, that instruction is returned directly.
  Otherwise, the signal is routed through the router to find matching instructions.

  ## Returns
  - `{:ok, instructions}` - List of matching instructions
  - `{:error, reason}` - Failed to route signal

  ## Examples

      {:ok, instructions} = Router.route(state, signal)
      Enum.each(instructions, &execute_instruction/1)
  """
  @spec route(ServerState.t(), Signal.t()) :: {:ok, [term()]} | {:error, term()}
  def route(%ServerState{} = state, %Signal{} = signal) do
    dbug("Routing signal", state: state, signal: signal)

    case signal.data do
      %Instruction{} = instruction ->
        dbug("Using explicit instruction from signal", instruction: instruction)
        {:ok, [instruction]}

      _ ->
        dbug("Routing through router")

        case Router.route(state.router, signal) do
          {:ok, []} ->
            dbug("No matching routes found for signal type", type: signal.type)
            {:error, :no_matching_route}

          {:ok, instructions} ->
            dbug("Signal routed successfully", instructions: instructions)
            {:ok, instructions}

          {:error, reason} ->
            dbug("Failed to route signal", error: reason)
            {:error, reason}
        end
    end
  end

  def route(%ServerState{} = _state, invalid) do
    dbug("Invalid signal for routing", signal: invalid)
    {:error, Error.validation_error("Invalid signal for routing", %{signal: invalid})}
  end
end
