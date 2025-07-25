defmodule Jido.Actions.StateManager do
  @moduledoc """
  Provides generic actions for managing state within an agent.

  This module implements the Jido.Action behavior and offers a collection
  of actions for getting, setting, updating, and deleting values in an agent's state.
  """

  use Jido.Action,
    name: "state_manager",
    description: "Generic actions for state management"

  require Logger
  alias Jido.Agent.Directive.StateModification

  defmodule Get do
    @moduledoc """
    Action for retrieving a value from the agent's state.

    Gets a value from the agent's state at the specified path.
    """

    use Jido.Action,
      name: "get",
      description: "Get a value from the state at a given path",
      schema: [
        path: [type: {:list, :atom}, required: true]
      ]

    @spec run(map(), map()) :: {:ok, map()} | {:ok, map(), any()} | {:error, any()}
    @impl true
    def run(params, context) do
      value = get_in(context.state, params.path)
      {:ok, %{value: value}, []}
    end
  end

  defmodule Set do
    @moduledoc """
    Action for setting a value in the agent's state.

    Sets a value in the agent's state at the specified path.
    """

    use Jido.Action,
      name: "set",
      description: "Set a value in the state at a given path",
      schema: [
        path: [type: {:list, :atom}, required: true],
        value: [type: :any, required: true]
      ]

    @spec run(map(), map()) :: {:ok, map()} | {:ok, map(), any()} | {:error, any()}
    @impl true
    def run(params, context) do
      # First ensure all intermediate maps exist
      directives = ensure_path_exists(params.path, context.state)

      # Then add our set directive
      directives =
        directives ++
          [
            %StateModification{
              op: :set,
              path: params.path,
              value: params.value
            }
          ]

      {:ok, context.state, directives}
    end

    defp ensure_path_exists(path, state) do
      path
      |> Enum.reduce({[], []}, fn key, {current_path, directives} ->
        current_path = current_path ++ [key]

        if length(current_path) < length(path) and get_in(state, current_path) == nil do
          {current_path,
           directives ++
             [
               %StateModification{
                 op: :set,
                 path: current_path,
                 value: %{}
               }
             ]}
        else
          {current_path, directives}
        end
      end)
      |> elem(1)
    end
  end

  defmodule Update do
    @moduledoc """
    Action for updating a value in the agent's state.

    Updates a value in the agent's state at the specified path using
    a transformation function.
    """

    use Jido.Action,
      name: "update",
      description: "Update a value in the state at a given path with a new value",
      schema: [
        path: [type: {:list, :atom}, required: true],
        value: [type: :any, required: true]
      ]

    @spec run(map(), map()) :: {:ok, map()} | {:ok, map(), any()} | {:error, any()}
    @impl true
    def run(params, context) do
      # First ensure all intermediate maps exist
      directives = ensure_path_exists(params.path, context.state)

      # Then add our update directive
      directives =
        directives ++
          [
            %StateModification{
              op: :set,
              path: params.path,
              value: params.value
            }
          ]

      {:ok, context.state, directives}
    end

    defp ensure_path_exists(path, state) do
      path
      |> Enum.reduce({[], []}, fn key, {current_path, directives} ->
        current_path = current_path ++ [key]

        if length(current_path) < length(path) and get_in(state, current_path) == nil do
          {current_path,
           directives ++
             [
               %StateModification{
                 op: :set,
                 path: current_path,
                 value: %{}
               }
             ]}
        else
          {current_path, directives}
        end
      end)
      |> elem(1)
    end
  end

  defmodule Delete do
    @moduledoc """
    Action for deleting a value from the agent's state.

    Removes a value from the agent's state at the specified path.
    """

    use Jido.Action,
      name: "delete",
      description: "Delete a value from the state at a given path",
      schema: [
        path: [type: {:list, :atom}, required: true]
      ]

    require Logger

    @spec run(map(), map()) :: {:ok, map()} | {:ok, map(), any()} | {:error, any()}
    @impl true
    def run(params, context) do
      Logger.info("Delete action called with path: #{inspect(params.path)}")
      Logger.debug("Current state before delete: #{inspect(context.state)}")

      case params.path do
        [] ->
          Logger.info("Empty path, returning original state")
          {:ok, context.state, []}

        path ->
          Logger.info("Deleting path: #{inspect(path)}")

          {:ok, context.state,
           [
             %StateModification{
               op: :delete,
               path: path,
               value: nil
             }
           ]}
      end
    end
  end
end
