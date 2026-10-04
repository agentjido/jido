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
  use Jido.Plugin

  @impl true
  defdelegate state_spec(opts), to: Jido.Examples.Applications.Subscription.Plugin.Agent

  @impl true
  defdelegate directives(opts), to: Jido.Examples.Applications.Subscription.Plugin.Agent

  @impl true
  defdelegate reduce(reduction, opts), to: Jido.Examples.Applications.Subscription.Plugin.Agent

  @impl true
  defdelegate dispatch(runtime, directive, context, opts),
    to: Jido.Examples.Applications.Subscription.Plugin.Server

  @impl true
  defdelegate await_ready(runtime, opts),
    to: Jido.Examples.Applications.Subscription.Plugin.Server

  @impl true
  defdelegate child_spec(init), to: Jido.Examples.Applications.Subscription.Plugin.Server
  alias Jido.Examples.Applications.Subscription.{Subscribe, Unsubscribe}

  def subscribe(topic, config \\ %{}), do: %Subscribe{topic: topic, config: config}
  def unsubscribe(topic), do: %Unsubscribe{topic: topic}
end

defmodule Jido.Examples.Applications.Subscription.Plugin.Agent do
  @behaviour Jido.Plugin
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
  @behaviour Jido.Plugin
  alias Jido.Plugin.{DirectiveContext, Init}
  alias Jido.Examples.Applications.Subscription.Runtime

  @impl true
  def dispatch(runtime, _directive, %DirectiveContext{} = context, _opts),
    do: GenServer.call(runtime, {:reconcile, context.plugin_state.desired, context.state_version})

  @impl true
  def await_ready(runtime, _opts), do: GenServer.call(runtime, :await_ready)

  @impl true
  def child_spec(%Init{} = init),
    do: Supervisor.child_spec({Runtime, init}, id: Jido.Examples.Applications.Subscription.Plugin)
end

defmodule Jido.Examples.Applications.Subscription.Runtime do
  @moduledoc "Owns replaceable resources for committed subscription state."
  use GenServer

  alias Jido.Plugin.Init

  def start_link(%Init{} = init), do: GenServer.start_link(__MODULE__, init)
  def external(runtime), do: GenServer.call(runtime, :external)
  def info(runtime), do: GenServer.call(runtime, :info)
  def input(runtime, resource, text), do: GenServer.call(runtime, {:input, resource, text})

  @impl true
  def init(%Init{} = init) do
    Process.flag(:trap_exit, true)

    state = %{
      init: init,
      bootstrap: %{plugin_state: init.plugin_state, state_version: init.state_version},
      external: %{},
      resources: %{},
      state_version: init.state_version
    }

    {:ok, state, {:continue, :restore}}
  end

  @impl true
  def handle_continue(:restore, state),
    do: {:noreply, reconcile(state, state.init.plugin_state.desired, state.init.state_version)}

  @impl true
  def handle_call(:await_ready, _from, state), do: {:reply, :ok, state}
  def handle_call(:external, _from, state), do: {:reply, state.external, state}

  def handle_call(:info, _from, state) do
    info = Map.take(state, [:bootstrap, :external, :resources, :state_version])
    {:reply, info, state}
  end

  def handle_call({:reconcile, desired, state_version}, _from, state),
    do: {:reply, :ok, reconcile(state, desired, state_version)}

  def handle_call({:input, resource, text}, _from, state) do
    case Enum.find(state.resources, fn {_topic, current} -> current == resource end) do
      {topic, _current} ->
        signal =
          Jido.Signal.new!(
            "examples.applications.subscription.input",
            %{topic: topic, text: text},
            source: "/examples/applications/subscription/runtime"
          )

        {:reply, Jido.AgentServer.cast(state.init.agent_server, signal), state}

      nil ->
        {:reply, {:error, :stale_resource}, state}
    end
  end

  @impl true
  def handle_info({:EXIT, _pid, :normal}, state), do: {:noreply, state}
  def handle_info({:EXIT, _pid, reason}, state), do: {:stop, reason, state}

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.resources, fn {_topic, resource} -> stop_resource(resource.pid) end)
  end

  defp reconcile(state, desired, state_version) do
    Enum.each(state.resources, fn {_topic, resource} -> stop_resource(resource.pid) end)

    resources =
      Map.new(desired, fn {topic, config} ->
        pid = spawn_link(fn -> resource_loop() end)
        {topic, %{pid: pid, topic: topic, config: config, generation: state_version}}
      end)

    %{state | external: desired, resources: resources, state_version: state_version}
  end

  defp resource_loop do
    receive do
      :close -> :ok
    end
  end

  defp stop_resource(pid) do
    monitor = Process.monitor(pid)
    send(pid, :close)

    receive do
      {:DOWN, ^monitor, :process, ^pid, _reason} -> :ok
    after
      1_000 -> Process.demonitor(monitor, [:flush])
    end
  end
end
