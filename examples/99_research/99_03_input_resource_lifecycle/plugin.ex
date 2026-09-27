defmodule Jido.Examples.RuntimeReconstruction.SetFeed do
  @moduledoc "Replaces the desired feed owned by the Plugin."
  @schema Zoi.struct(__MODULE__, %{feed: Zoi.string() |> Zoi.min(1)})
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
  def schema, do: @schema
  def validate(%__MODULE__{} = directive), do: Zoi.parse(@schema, directive)
end

defmodule Jido.Examples.RuntimeReconstruction.Plugin do
  @moduledoc "Owns desired feed state and reconciles the replaceable runtime."
  use Jido.Plugin

  @impl true
  defdelegate state_spec(opts), to: Jido.Examples.RuntimeReconstruction.Plugin.Agent

  @impl true
  defdelegate directives(opts), to: Jido.Examples.RuntimeReconstruction.Plugin.Agent

  @impl true
  defdelegate reduce(reduction, opts), to: Jido.Examples.RuntimeReconstruction.Plugin.Agent

  @impl true
  defdelegate child_spec(init), to: Jido.Examples.RuntimeReconstruction.Plugin.Server

  @impl true
  defdelegate dispatch(runtime, directive, context, opts),
    to: Jido.Examples.RuntimeReconstruction.Plugin.Server
end

defmodule Jido.Examples.RuntimeReconstruction.Plugin.Agent do
  @behaviour Jido.Plugin

  alias Jido.Examples.RuntimeReconstruction.SetFeed

  def state_spec(_opts) do
    {:feed, Zoi.object(%{name: Zoi.string() |> Zoi.default("A")}) |> Zoi.default(%{name: "A"})}
  end

  def directives(_opts), do: [SetFeed]

  def reduce(reduction, _opts) do
    state = reduction.plugin_state
    directives = Enum.filter(reduction.directives, &match?(%SetFeed{}, &1))

    next_state =
      Enum.reduce(directives, state, fn
        %SetFeed{feed: feed}, _state -> %{name: feed}
      end)

    {:ok, next_state}
  end
end

defmodule Jido.Examples.RuntimeReconstruction.Plugin.Server do
  @behaviour Jido.Plugin
  alias Jido.Examples.RuntimeReconstruction.Runtime

  def child_spec(init),
    do: Supervisor.child_spec({Runtime, init}, id: Jido.Examples.RuntimeReconstruction.Plugin)

  def dispatch(runtime, _directive, _context, _opts), do: GenServer.call(runtime, :reconcile)
end
