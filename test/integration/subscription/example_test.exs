defmodule JidoTest.Integration.Subscription.Subscribe do
  @schema Zoi.struct(
            __MODULE__,
            %{
              topic: Zoi.string(),
              config: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema
end

defmodule JidoTest.Integration.Subscription.Unsubscribe do
  @schema Zoi.struct(
            __MODULE__,
            %{topic: Zoi.string()},
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema
end

defmodule JidoTest.Integration.Subscription.Plugin do
  use Jido.Plugin

  alias Jido.Plugin.{DirectiveContext, Init}
  alias JidoTest.Integration.Subscription.{Runtime, Subscribe, Unsubscribe}

  @state_schema Zoi.object(%{
                  desired: Zoi.map() |> Zoi.default(%{})
                })
                |> Zoi.default(%{desired: %{}})

  def subscribe(topic, config \\ %{}), do: %Subscribe{topic: topic, config: config}
  def unsubscribe(topic), do: %Unsubscribe{topic: topic}

  @impl Jido.Plugin
  def state_spec(_opts), do: {:subscriptions, @state_schema}

  @impl Jido.Plugin
  def directives(_opts), do: [Subscribe, Unsubscribe]

  @impl Jido.Plugin
  def validate_directive(%Subscribe{} = directive, _opts),
    do: Zoi.parse(Subscribe.schema(), Map.from_struct(directive))

  def validate_directive(%Unsubscribe{} = directive, _opts),
    do: Zoi.parse(Unsubscribe.schema(), Map.from_struct(directive))

  @impl Jido.Plugin
  def update_state(state, directives, _opts) do
    next =
      Enum.reduce(directives, state, fn
        %Subscribe{topic: topic, config: config}, state ->
          put_in(state, [:desired, topic], config)

        %Unsubscribe{topic: topic}, state ->
          update_in(state, [:desired], &Map.delete(&1, topic))
      end)

    {:ok, next}
  end

  @impl Jido.Plugin
  def dispatch(runtime, _directive, %DirectiveContext{} = context, _opts) do
    GenServer.call(runtime, {:reconcile, context.plugin_state.desired})
  end

  @impl Jido.Plugin
  def await_ready(runtime, _opts), do: GenServer.call(runtime, :await_ready)

  def child_spec(%Init{} = init) do
    Supervisor.child_spec({Runtime, init}, id: __MODULE__)
  end
end

defmodule JidoTest.Integration.Subscription.Runtime do
  use GenServer

  alias Jido.Plugin
  alias Jido.Plugin.Init

  def start_link(%Init{} = init), do: GenServer.start_link(__MODULE__, init)

  def external(runtime), do: GenServer.call(runtime, :external)
  def fail_next(runtime), do: GenServer.call(runtime, :fail_next)

  @impl true
  def init(%Init{} = init) do
    {:ok, %{init: init, external: %{}, fail_next?: false}, {:continue, :restore}}
  end

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
  def handle_call(:fail_next, _from, state), do: {:reply, :ok, %{state | fail_next?: true}}

  def handle_call({:reconcile, _desired}, _from, %{fail_next?: true} = state) do
    {:reply, {:error, :simulated_reconcile_failure}, %{state | fail_next?: false}}
  end

  def handle_call({:reconcile, desired}, _from, state) do
    {:reply, :ok, %{state | external: desired}}
  end
end

defmodule JidoTest.Integration.Subscription.Change do
  use Jido.Action, name: "pressure_subscription_change"

  alias JidoTest.Integration.Subscription.Plugin

  @impl Jido.Action
  def run(%{operation: :subscribe, topic: topic, config: config}, context) do
    next_state = %{context.agent_state | changes: context.agent_state.changes + 1}
    {:ok, next_state, [Plugin.subscribe(topic, config)]}
  end

  def run(%{operation: :unsubscribe, topic: topic}, context) do
    next_state = %{context.agent_state | changes: context.agent_state.changes + 1}
    {:ok, next_state, [Plugin.unsubscribe(topic)]}
  end
end

defmodule JidoTest.Integration.Subscription.Agent do
  use Jido.Agent, name: "pressure_subscription_agent"

  agent do
    schema Zoi.object(%{changes: Zoi.integer() |> Zoi.default(0)})
    plugin JidoTest.Integration.Subscription.Plugin
  end

  routes do
    route "subscription.change", JidoTest.Integration.Subscription.Change
  end
end
