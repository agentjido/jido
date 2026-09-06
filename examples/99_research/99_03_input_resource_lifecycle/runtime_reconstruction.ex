defmodule Jido.Examples.RuntimeReconstruction.SetFeed do
  @moduledoc false
  @schema Zoi.struct(__MODULE__, %{feed: Zoi.string()})
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
  def schema, do: @schema
end

defmodule Jido.Examples.RuntimeReconstruction.Plugin do
  @moduledoc "Saves desired feed configuration and owns one disposable runtime."
  use Jido.Plugin
  alias Jido.Examples.RuntimeReconstruction.{SetFeed, Runtime}

  def state_spec(_),
    do:
      {:feed, Zoi.object(%{name: Zoi.string() |> Zoi.default("A")}) |> Zoi.default(%{name: "A"})}

  def directives(_), do: [SetFeed]
  def validate_directive(directive, _), do: Zoi.parse(SetFeed.schema(), directive)

  def update_state(state, directives, _) do
    {:ok, Enum.reduce(directives, state, fn %SetFeed{feed: feed}, _ -> %{name: feed} end)}
  end

  def child_spec(init), do: Supervisor.child_spec({Runtime, init}, id: __MODULE__)
  def dispatch(runtime, _, _, _), do: GenServer.call(runtime, :reconcile)
end

defmodule Jido.Examples.RuntimeReconstruction.Runtime do
  @moduledoc """
  Pulls current owned state through Jido.Plugin.state/1 after startup.
  The resource is a linked disposable process. No process handle enters Agent state.
  """
  use GenServer
  def start_link(init), do: GenServer.start_link(__MODULE__, init)
  def inspect_runtime(pid), do: GenServer.call(pid, :inspect)
  def input(pid, feed, text), do: GenServer.call(pid, {:input, feed, text})

  @impl true
  def init(init) do
    send(Keyword.fetch!(init.options, :observer), {:feed_runtime, self(), init})
    {:ok, %{init: init, resource: nil, feed: nil}, {:continue, :reconcile}}
  end

  @impl true
  def handle_continue(:reconcile, state) do
    case reconcile(state) do
      {:ok, next} -> {:noreply, next}
      {:error, reason} -> {:stop, reason, state}
    end
  end

  @impl true
  def handle_call(:reconcile, _, state) do
    case reconcile(state) do
      {:ok, next} -> {:reply, :ok, next}
      error -> {:reply, error, state}
    end
  end

  def handle_call(:inspect, _, state), do: {:reply, state, state}

  def handle_call({:input, feed, text}, _, %{feed: feed} = state) do
    signal = Jido.Signal.new!("feed.input", %{feed: feed, text: text}, source: "/examples/feed")
    {:reply, Jido.AgentServer.cast(state.init.agent_server, signal), state}
  end

  def handle_call({:input, _, _}, _, state), do: {:reply, {:error, :stale_feed}, state}
  @impl true
  def terminate(_, state), do: stop_resource(state.resource)

  defp reconcile(state) do
    with {:ok, %{name: feed}} <- Jido.Plugin.state(state.init) do
      stop_resource(state.resource)

      resource =
        spawn_link(fn ->
          receive do
            :close -> :ok
          end
        end)

      {:ok, %{state | resource: resource, feed: feed}}
    end
  end

  defp stop_resource(nil), do: :ok

  defp stop_resource(pid) do
    ref = Process.monitor(pid)
    send(pid, :close)

    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    after
      1_000 -> Process.demonitor(ref, [:flush])
    end
  end
end

defmodule Jido.Examples.RuntimeReconstruction do
  @moduledoc "A feed Agent with saved desired configuration and a replaceable input runtime."
  use Jido.Agent, name: "research_runtime_reconstruction"

  agent do
    schema Zoi.object(%{items: Zoi.list(Zoi.string()) |> Zoi.default([])})
    plugin __MODULE__.Plugin
  end

  routes do
    signal_source "/examples/feed"

    route "feed.select" do
      action %{name: name},
        name: "research_feed_select",
        schema: Zoi.object(%{name: Zoi.string()}),
        context: context do
        {:ok, context.agent_state, [%Jido.Examples.RuntimeReconstruction.SetFeed{feed: name}]}
      end

      define :select, args: [:name]
    end

    route "feed.input" do
      action %{feed: feed, text: text},
        name: "research_feed_input",
        schema: Zoi.object(%{feed: Zoi.string(), text: Zoi.string()}),
        context: context do
        if context.agent_state.feed.name == feed do
          {:ok, %{context.agent_state | items: context.agent_state.items ++ [text]}}
        else
          {:error, Jido.Action.Error.validation_error("stale feed")}
        end
      end
    end
  end

  def new_for(observer) do
    definition = Jido.Agent.definition(new!())
    Jido.Agent.new!(%{definition | plugins: [{__MODULE__.Plugin, observer: observer}]})
  end
end
