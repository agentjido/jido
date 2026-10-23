defmodule JidoTest.AgentServer.PluginRuntime.ConfigurationSupport do
  alias Jido.Agent
  alias JidoTest.AgentServer.Fixtures, as: F

  defmodule Root do
    use GenServer
    def start_link(init), do: GenServer.start_link(__MODULE__, init)

    def init(init) do
      send(init.options[:observer], {:plugin_started, self(), init})

      if init.options[:fail_start],
        do: {:stop, :controlled_start_failure},
        else: {:ok, %{init: init, paused: false}}
    end

    def handle_call({:pause, mode}, _, state) do
      if mode == :fail,
        do: {:reply, {:error, :pause_failed}, state},
        else: {:reply, :ok, %{state | paused: true}}
    end

    def handle_call(:resume, _, state), do: {:reply, :ok, %{state | paused: false}}
    def handle_call(:paused?, _, state), do: {:reply, state.paused, state}
  end

  defmodule Cache do
    use Jido.Plugin
    def state_spec(_), do: {:cache, Zoi.integer() |> Zoi.default(5)}
    def child_spec(init), do: %{id: __MODULE__, start: {Root, :start_link, [init]}}

    def quiesce(runtime, opts) do
      send(opts[:observer], {:quiescing, runtime, self()})
      if opts[:gate], do: receive(do: (:release -> :ok))
      GenServer.call(runtime, {:pause, opts[:pause_mode]})
    end

    def after_commit(runtime, commit, opts) do
      send(opts[:observer], {:composition_hook, __MODULE__, runtime, commit.state_version})
      :ok
    end

    def resume(runtime, opts) do
      send(opts[:observer], {:resuming, runtime})
      GenServer.call(runtime, :resume)
    end
  end

  defmodule Observer do
    use Jido.Plugin

    def after_commit(runtime, commit, opts) do
      send(opts[:observer], {:composition_hook, __MODULE__, runtime, commit.state_version})
      :ok
    end
  end

  defmodule CacheTwo do
    use Jido.Plugin
    def state_spec(_), do: {:cache_two, Zoi.integer() |> Zoi.default(7)}
    def child_spec(init), do: %{id: __MODULE__, start: {Root, :start_link, [init]}}

    def quiesce(runtime, opts) do
      send(opts[:observer], {:quiescing, runtime, self()})
      GenServer.call(runtime, {:pause, opts[:pause_mode]})
    end

    def resume(runtime, _opts), do: GenServer.call(runtime, :resume)
  end

  defmodule UnsafeCache do
    use Jido.Plugin
    def child_spec(init), do: %{id: __MODULE__, start: {Root, :start_link, [init]}}
  end

  def agent(topology \\ %{}, plugins \\ []) do
    Agent.define!(%{
      name: "composed",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
      routes: [
        %{
          path: "work",
          handler: %{kind: :action, target: F.Work},
          state: %{source: :output, path: []}
        }
      ],
      topology: topology,
      extensions:
        Enum.map(plugins, fn declaration ->
          {provider, options} =
            case declaration do
              {provider, options} -> {provider, options}
              provider -> {provider, []}
            end

          %{id: provider.id(), provider: provider, vsn: provider.vsn(), data: Map.new(options)}
        end)
    })
    |> Agent.instantiate!(id: "composed")
  end
end
