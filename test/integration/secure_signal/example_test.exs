Code.require_file("../identity/example_test.exs", __DIR__)

defmodule JidoTest.Integration.SecureSignal.Runtime do
  use GenServer

  alias Jido.Plugin.Init
  alias JidoTest.Integration.Crypto

  def start_link(%Init{} = init), do: GenServer.start_link(__MODULE__, init)

  def decrypt(runtime, signal, envelope),
    do: GenServer.call(runtime, {:decrypt, signal, envelope})

  def encrypt(runtime, signal, plaintext),
    do: GenServer.call(runtime, {:encrypt, signal, plaintext})

  @impl true
  def init(%Init{options: options}) do
    {:ok, %{key_id: Keyword.fetch!(options, :key_id), key: Crypto.secure_key()}}
  end

  @impl true
  def handle_call({:decrypt, signal, envelope}, _from, state) do
    {:reply, Crypto.decrypt(signal, state.key, envelope), state}
  end

  def handle_call({:encrypt, signal, plaintext}, _from, state) do
    {:reply, {:ok, Crypto.encrypt(signal, state.key, plaintext)}, state}
  end
end

defmodule JidoTest.Integration.SecureSignal.Plugin do
  use Jido.Plugin

  alias Jido.Agent.Command
  alias Jido.Plugin.{Init, SignalContext}
  alias JidoTest.Integration.SecureSignal.Runtime

  @impl Jido.Plugin
  def admit(runtime, %Command{signal: %{data: %{"secure" => envelope}}} = command, _opts) do
    with {:ok, plaintext} <- Runtime.decrypt(runtime, command.signal, envelope) do
      signal = %{command.signal | data: Map.delete(command.signal.data, "secure")}
      context = Map.put(command.context, :secure, plaintext)
      {:ok, %{command | signal: signal, context: context}}
    end
  end

  def admit(_runtime, _command, _opts), do: {:error, :secure_data_required}

  @impl Jido.Plugin
  def prepare_dispatch(
        runtime,
        %Jido.Signal{data: %{"secure" => plaintext}} = signal,
        %SignalContext{},
        _opts
      ) do
    with {:ok, envelope} <- Runtime.encrypt(runtime, signal, plaintext) do
      {:ok, %{signal | data: Map.put(signal.data, "secure", envelope)}}
    end
  end

  def prepare_dispatch(_runtime, signal, %SignalContext{}, _opts), do: {:ok, signal}

  def child_spec(%Init{} = init) do
    Supervisor.child_spec({Runtime, init}, id: __MODULE__)
  end
end

defmodule JidoTest.Integration.SecureSignal.Accept do
  use Jido.Action, name: "integration_secure_signal_accept"

  alias Jido.Agent.Directive
  alias Jido.Signal

  @impl Jido.Action
  def run(%{"message_id" => message_id}, %{identity: public_key, secure: secure} = context) do
    reply =
      Signal.new!(
        "secure.accepted",
        %{
          "message_id" => message_id,
          "secure" => %{"receipt" => secure["secret"] <> ":accepted"}
        },
        source: "/secure/agent"
      )

    next_state = %{
      context.agent_state
      | accepted: context.agent_state.accepted + 1,
        peer: Base.encode16(public_key, case: :lower)
    }

    {:ok, next_state, [Directive.emit(reply)]}
  end
end

defmodule JidoTest.Integration.SecureSignal.Agent do
  use Jido.Agent, name: "integration_secure_signal_agent"

  agent do
    schema Zoi.object(%{
             accepted: Zoi.integer() |> Zoi.default(0),
             peer: Zoi.string() |> Zoi.default("")
           })

    plugin JidoTest.Integration.Identity.Plugin,
      config: [
        trusted_public_key: elem(JidoTest.Integration.Crypto.peer_key_pair(), 0),
        signing_key_id: :agent_identity
      ]

    plugin JidoTest.Integration.SecureSignal.Plugin, config: [key_id: :test_channel]
  end

  routes do
    route "secure.request", JidoTest.Integration.SecureSignal.Accept
  end
end
