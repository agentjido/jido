defmodule Jido.Examples.RuntimeReconstruction.SetFeed do
  @moduledoc "Replaces the desired feed owned by the Plugin."
  @schema Zoi.struct(__MODULE__, %{feed: Zoi.string() |> Zoi.min(1)})
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
  def schema, do: @schema
end

defmodule Jido.Examples.RuntimeReconstruction.Plugin do
  @moduledoc "Owns desired feed state and reconciles the replaceable runtime."
  use Jido.Plugin

  alias Jido.Examples.RuntimeReconstruction.{Runtime, SetFeed}

  def state_spec(_opts) do
    {:feed, Zoi.object(%{name: Zoi.string() |> Zoi.default("A")}) |> Zoi.default(%{name: "A"})}
  end

  def directives(_opts), do: [SetFeed]
  def validate_directive(directive, _opts), do: Zoi.parse(SetFeed.schema(), directive)

  def update_state(state, directives, _opts) do
    next_state =
      Enum.reduce(directives, state, fn
        %SetFeed{feed: feed}, _state -> %{name: feed}
      end)

    {:ok, next_state}
  end

  def child_spec(init), do: Supervisor.child_spec({Runtime, init}, id: __MODULE__)
  def dispatch(runtime, _directive, _context, _opts), do: GenServer.call(runtime, :reconcile)
end
