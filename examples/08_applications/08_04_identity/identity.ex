defmodule Jido.Examples.Applications.Identity.Runtime do
  use GenServer

  alias Jido.Plugin.Init
  alias Jido.Examples.Applications.Crypto

  def start_link(%Init{} = init), do: GenServer.start_link(__MODULE__, init)

  def verify(runtime, signal), do: GenServer.call(runtime, {:verify, signal})
  def sign(runtime, signal), do: GenServer.call(runtime, {:sign, signal})

  @impl true
  def init(%Init{options: options}) do
    {public_key, private_key} = Crypto.agent_key_pair()

    {:ok,
     %{
       trusted_public_key: Keyword.fetch!(options, :trusted_public_key),
       signing_key_id: Keyword.fetch!(options, :signing_key_id),
       public_key: public_key,
       private_key: private_key,
       seen_nonces: MapSet.new()
     }}
  end

  @impl true
  def handle_call({:verify, signal}, _from, state) do
    case Crypto.verify(signal, state.trusted_public_key) do
      {:ok, nonce} ->
        if MapSet.member?(state.seen_nonces, nonce) do
          {:reply, {:error, :replayed_signal}, state}
        else
          {:reply, {:ok, state.trusted_public_key},
           %{state | seen_nonces: MapSet.put(state.seen_nonces, nonce)}}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:sign, signal}, _from, state) do
    result = Crypto.sign(signal, state.private_key, state.public_key)
    {:reply, result, state}
  end
end

defmodule Jido.Examples.Applications.Identity.Plugin do
  use Jido.Plugin

  alias Jido.Agent.Command
  alias Jido.Plugin.{Init, SignalContext}
  alias Jido.Examples.Applications.Identity.Runtime

  @impl Jido.Plugin
  def admit(runtime, %Command{} = command, _opts) do
    case Runtime.verify(runtime, command.signal) do
      {:ok, public_key} ->
        {:ok, %{command | context: Map.put(command.context, :identity, public_key)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Jido.Plugin
  def prepare_dispatch(runtime, signal, %SignalContext{}, _opts) do
    Runtime.sign(runtime, signal)
  end

  def child_spec(%Init{} = init) do
    Supervisor.child_spec({Runtime, init}, id: __MODULE__)
  end
end

defmodule Jido.Examples.Applications.Identity.Accept do
  use Jido.Action, name: "integration_identity_accept"

  alias Jido.Agent.Directive
  alias Jido.Signal

  @impl Jido.Action
  def run(%{"challenge" => challenge}, %{identity: public_key} = context) do
    reply =
      Signal.new!(
        "identity.accepted",
        %{"challenge" => challenge},
        source: "/identity/agent"
      )

    next_state = %{
      context.agent_state
      | accepted: context.agent_state.accepted + 1,
        last_public_key: Base.encode16(public_key, case: :lower)
    }

    {:ok, next_state, [Directive.emit(reply)]}
  end
end

defmodule Jido.Examples.Applications.Identity.Agent do
  use Jido.Agent, name: "integration_identity_agent"

  agent do
    schema Zoi.object(%{
             accepted: Zoi.integer() |> Zoi.default(0),
             last_public_key: Zoi.string() |> Zoi.default("")
           })

    plugin Jido.Examples.Applications.Identity.Plugin,
      config: [
        trusted_public_key: elem(Jido.Examples.Applications.Crypto.peer_key_pair(), 0),
        signing_key_id: :agent_identity
      ]
  end

  routes do
    route "identity.challenge", Jido.Examples.Applications.Identity.Accept
  end
end
