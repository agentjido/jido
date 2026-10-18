defmodule Jido.ConfigRuntimeTest do
  use JidoTest.Case, async: false

  alias Jido.Agent
  alias Jido.AgentServer, as: Server
  alias JidoTest.AgentServerAssertions

  defmodule Connection do
    use Jido.Plugin, id: "test.environment.connection"

    @impl true
    def child_spec(init), do: Supervisor.child_spec({__MODULE__.Runtime, init}, id: __MODULE__)
  end

  defmodule Connection.Runtime do
    use GenServer

    def start_link(init), do: GenServer.start_link(__MODULE__, init)

    @impl true
    def init(init) do
      case Jido.Config.resolve(init.options) do
        {:ok, options} -> {:ok, options}
        {:error, error} -> {:stop, error}
      end
    end

    @impl true
    def handle_call(:config, _from, config), do: {:reply, config, config}
  end

  test "a Plugin resolves once at startup and resolves again after snapshot restore", %{
    jido: jido
  } do
    name = "JIDO_RUNTIME_ENV_#{System.unique_integer([:positive])}"
    on_exit(fn -> System.delete_env(name) end)

    data = %{credentials: %{token: Jido.Config.env(name)}}

    agent =
      Agent.define!(%{
        name: "environment_runtime",
        extensions: [%{id: Connection.id(), provider: Connection, vsn: 1, data: data}]
      })
      |> Agent.instantiate!(id: unique_id("environment"))

    System.put_env(name, "private-token-first")
    assert {:ok, server} = AgentServerAssertions.start_agent(jido, agent)
    %{pid: runtime} = AgentServerAssertions.plugin(server, Connection)
    assert GenServer.call(runtime, :config) == [credentials: %{token: "private-token-first"}]

    System.put_env(name, "private-token-second")
    assert GenServer.call(runtime, :config) == [credentials: %{token: "private-token-first"}]

    assert Server.agent(server) === agent
    assert {:ok, snapshot} = Jido.Persistence.snapshot(Server.agent(server))
    refute inspect(snapshot) =~ "private-token"
    assert :ok = Server.stop(server)

    assert {:ok, ^agent} = Jido.Persistence.restore(snapshot)
    assert {:ok, restored} = AgentServerAssertions.start_agent(jido, agent)
    %{pid: replacement} = AgentServerAssertions.plugin(restored, Connection)
    assert replacement != runtime
    assert GenServer.call(replacement, :config) == [credentials: %{token: "private-token-second"}]
    assert Server.agent(restored) === agent
    assert :ok = Server.stop(restored)
  end
end
