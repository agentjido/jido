defmodule Jido.Examples.Applications.Subscription.Subscribe do
  @moduledoc "Adds or replaces one desired external subscription."

  @schema Zoi.struct(
            __MODULE__,
            %{topic: Zoi.string(), config: Zoi.map() |> Zoi.default(%{})},
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
  def schema, do: @schema
  def validate(%__MODULE__{} = directive), do: Zoi.parse(@schema, Map.from_struct(directive))
end

defmodule Jido.Examples.Applications.Subscription.Unsubscribe do
  @moduledoc "Removes one desired external subscription."

  @schema Zoi.struct(__MODULE__, %{topic: Zoi.string()}, coerce: true)
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
  def schema, do: @schema
  def validate(%__MODULE__{} = directive), do: Zoi.parse(@schema, Map.from_struct(directive))
end

defmodule Jido.Examples.Applications.Subscription.Plugin do
  @moduledoc "Owns desired subscription state and reconciles a runtime projection."
  use Jido.Plugin, agent: __MODULE__.Agent, agent_server: __MODULE__.Server
  alias Jido.Examples.Applications.Subscription.{Subscribe, Unsubscribe}

  def subscribe(topic, config \\ %{}), do: %Subscribe{topic: topic, config: config}
  def unsubscribe(topic), do: %Unsubscribe{topic: topic}
end

defmodule Jido.Examples.Applications.Subscription.Plugin.Agent do
  use Jido.Agent.Plugin
  alias Jido.Examples.Applications.Subscription.{Subscribe, Unsubscribe}

  @state_schema Zoi.object(%{desired: Zoi.map() |> Zoi.default(%{})})
                |> Zoi.default(%{desired: %{}})

  @impl true
  def state_spec(_opts), do: {:subscriptions, @state_schema}

  @impl true
  def directives(_opts), do: [Subscribe, Unsubscribe]

  @impl true
  def reduce(reduction, _opts) do
    state = reduction.plugin_state

    directives =
      Enum.filter(reduction.directives, &(match?(%Subscribe{}, &1) or match?(%Unsubscribe{}, &1)))

    next =
      Enum.reduce(directives, state, fn
        %Subscribe{topic: topic, config: config}, current ->
          put_in(current, [:desired, topic], config)

        %Unsubscribe{topic: topic}, current ->
          update_in(current, [:desired], &Map.delete(&1, topic))
      end)

    {:ok, next}
  end
end

defmodule Jido.Examples.Applications.Subscription.Plugin.Server do
  use Jido.AgentServer.Plugin
  alias Jido.Plugin.{DirectiveContext, Init}
  alias Jido.Examples.Applications.Subscription.Runtime

  @impl true
  def dispatch(runtime, _directive, %DirectiveContext{} = context, _opts),
    do: GenServer.call(runtime, {:reconcile, context.plugin_state.desired})

  @impl true
  def await_ready(runtime, _opts), do: GenServer.call(runtime, :await_ready)

  def child_spec(%Init{} = init),
    do: Supervisor.child_spec({Runtime, init}, id: Jido.Examples.Applications.Subscription.Plugin)
end

defmodule Jido.Examples.Applications.Subscription.Runtime do
  @moduledoc "Maintains the runtime projection of desired subscription state."
  use GenServer

  alias Jido.Plugin
  alias Jido.Plugin.Init

  def start_link(%Init{} = init), do: GenServer.start_link(__MODULE__, init)
  def external(runtime), do: GenServer.call(runtime, :external)

  @impl true
  def init(%Init{} = init), do: {:ok, %{init: init, external: %{}}, {:continue, :restore}}

  @impl true
  def handle_continue(:restore, state) do
    with {:ok, plugin_state} <- Plugin.state(state.init) do
      {:noreply, %{state | external: plugin_state.desired}}
    else
      {:error, reason} -> {:stop, {:restore_failed, reason}, state}
    end
  end

  @impl true
  def handle_call(:await_ready, _from, state), do: {:reply, :ok, state}
  def handle_call(:external, _from, state), do: {:reply, state.external, state}

  def handle_call({:reconcile, desired}, _from, state),
    do: {:reply, :ok, %{state | external: desired}}
end
