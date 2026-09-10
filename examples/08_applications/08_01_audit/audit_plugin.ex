defmodule Jido.Examples.Applications.Audit.Record do
  @moduledoc "Typed audit intent applied after the Agent Turn commits."

  @schema Zoi.struct(
            __MODULE__,
            %{
              event: Zoi.any(description: "Domain event to record"),
              outcome: Zoi.atom(description: "Event outcome")
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema
end

defmodule Jido.Examples.Applications.Audit.Plugin do
  @moduledoc "Owns committed audit state and reconciles its runtime projection."
  use Jido.Plugin

  alias Jido.Plugin.{DirectiveContext, Init}
  alias Jido.Examples.Applications.Audit.{Record, Runtime}

  @state_schema Zoi.object(%{events: Zoi.list(Zoi.any()) |> Zoi.default([])})
                |> Zoi.default(%{events: []})

  def record(event, outcome), do: %Record{event: event, outcome: outcome}

  @impl Jido.Plugin
  def state_spec(_opts), do: {:audit, @state_schema}

  @impl Jido.Plugin
  def directives(_opts), do: [Record]

  @impl Jido.Plugin
  def validate_directive(%Record{} = directive, _opts),
    do: Zoi.parse(Record.schema(), Map.from_struct(directive))

  @impl Jido.Plugin
  def update_state(state, directives, _opts) do
    events =
      Enum.reduce(directives, state.events, fn %Record{} = record, events ->
        events ++ [%{event: record.event, outcome: record.outcome}]
      end)

    {:ok, %{state | events: events}}
  end

  @impl Jido.Plugin
  def dispatch(runtime, _directive, %DirectiveContext{} = context, _opts),
    do: GenServer.call(runtime, {:reconcile, context.plugin_state.events})

  @impl Jido.Plugin
  def await_ready(runtime, _opts), do: GenServer.call(runtime, :await_ready)

  def child_spec(%Init{} = init), do: Supervisor.child_spec({Runtime, init}, id: __MODULE__)
end

defmodule Jido.Examples.Applications.Audit.Runtime do
  @moduledoc "Maintains the runtime projection of committed audit Plugin state."
  use GenServer

  alias Jido.Plugin
  alias Jido.Plugin.Init

  def start_link(%Init{} = init), do: GenServer.start_link(__MODULE__, init)
  def events(runtime), do: GenServer.call(runtime, :events)

  @impl true
  def init(%Init{} = init), do: {:ok, %{init: init, events: []}, {:continue, :restore}}

  @impl true
  def handle_continue(:restore, state) do
    with {:ok, plugin_state} <- Plugin.state(state.init) do
      {:noreply, %{state | events: plugin_state.events}}
    else
      {:error, reason} -> {:stop, {:restore_failed, reason}, state}
    end
  end

  @impl true
  def handle_call(:await_ready, _from, state), do: {:reply, :ok, state}
  def handle_call(:events, _from, state), do: {:reply, state.events, state}

  def handle_call({:reconcile, events}, _from, state),
    do: {:reply, :ok, %{state | events: events}}
end
