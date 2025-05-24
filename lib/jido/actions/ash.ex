defmodule Jido.Actions.Ash do
  defmodule Read do
    @moduledoc """
    Most straightforward implementation

    iex> Jido.Actions.Ash.Read.run(%{resource: Tunez.Artists, name: "U2"})
    []
    """
    use Jido.Action,
      name: "ash_read",
      description: "Execute an Ash read action on a resource",
      schema: [
        resource: [type: :atom, required: true, doc: "The Ash resource module"],
        action: [type: :atom, default: :read, doc: "The read action name"],
        params: [type: :map, default: %{}, doc: "Parameters for the action"],
        opts: [type: :keyword, default: [], doc: "Additional options for the query"]
      ]

    def run(params, context) do
      %{resource: resource, action: action, params: action_params, opts: opts} = params

      try do
        result =
          resource
          |> Ash.Query.for_read(action, action_params, opts)
          |> Ash.read!()

        {:ok, %{data: result, action_type: :read, resource: resource}}
      rescue
        error -> {:error, %{type: :ash_read_error, details: Exception.message(error)}}
      end
    end
  end

  defmodule ReadArtists do
    @moduledoc """
    Most straightforward implementation

    iex> Jido.Actions.Ash.ReadV2.run(%{name: "U2"})
    []
    """

    # Doesn't exist yet
    use Jido.Ash.ReadAction,
      name: "read_artists",
      description: "Read artists from the Tunez database",
      resource: Tunez.Artists,
      action: :read,
      # schema -> introspected from the Ash Action
  end
end

# Shorthand Helper ...

ash_read_action(Tunez.Artists, :read)
