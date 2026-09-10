defmodule Jido.Examples.Plugins.Identity.Plugin do
  @moduledoc "Verifies identity, rejects replay, and signs outbound Signals."

  use Jido.Plugin,
    agent: Jido.Examples.Plugins.Identity.Plugin.Agent,
    agent_server: Jido.Examples.Plugins.Identity.Plugin.Server,
    option_keys: [agent: [:trusted_public_key]]
end

defmodule Jido.Examples.Plugins.Identity.Plugin.Agent do
  @moduledoc false
  use Jido.Agent.Plugin

  alias Jido.Agent.Plugin.Preparation
  alias Jido.Examples.Plugins.Crypto

  @impl Jido.Agent.Plugin
  def prepare(%Preparation{signal: signal}, opts) do
    trusted_public_key = Keyword.fetch!(opts, :trusted_public_key)

    with {:ok, nonce} <- Crypto.verify(signal, trusted_public_key) do
      {:ok, %{public_key: trusted_public_key, nonce: nonce}}
    end
  end
end

defmodule Jido.Examples.Plugins.Identity.Plugin.Server do
  @moduledoc false
  use Jido.AgentServer.Plugin

  alias Jido.Agent.Command
  alias Jido.Plugin.{Init, SignalContext}
  alias Jido.Examples.Plugins.Identity.Plugin
  alias Jido.Examples.Plugins.Identity.Runtime

  @impl Jido.AgentServer.Plugin
  def admit(runtime, %Command{} = command, _opts) do
    with {:ok, %{nonce: nonce}} <- Map.fetch(command.plugin_inputs, Plugin),
         :ok <- Runtime.claim_nonce(runtime, nonce) do
      {:ok, command}
    else
      :error -> {:error, :identity_input_required}
      {:ok, _input} -> {:error, :invalid_identity_input}
      {:error, _reason} = error -> error
    end
  end

  @impl Jido.AgentServer.Plugin
  def prepare_dispatch(runtime, signal, %SignalContext{}, _opts),
    do: Runtime.sign(runtime, signal)

  def child_spec(%Init{} = init), do: Supervisor.child_spec({Runtime, init}, id: __MODULE__)
end

defmodule Jido.Examples.Plugins.Identity.Runtime do
  @moduledoc "Owns identity keys and the transient replay nonce set."
  use GenServer

  alias Jido.Examples.Plugins.Crypto
  alias Jido.Plugin.Init

  def start_link(%Init{} = init), do: GenServer.start_link(__MODULE__, init)
  def claim_nonce(runtime, nonce), do: GenServer.call(runtime, {:claim_nonce, nonce})
  def sign(runtime, signal), do: GenServer.call(runtime, {:sign, signal})

  @impl true
  def init(%Init{}) do
    {public_key, private_key} = Crypto.agent_key_pair()

    {:ok,
     %{
       public_key: public_key,
       private_key: private_key,
       seen_nonces: MapSet.new()
     }}
  end

  @impl true
  def handle_call({:claim_nonce, nonce}, _from, state) do
    if MapSet.member?(state.seen_nonces, nonce) do
      {:reply, {:error, :replayed_signal}, state}
    else
      {:reply, :ok, %{state | seen_nonces: MapSet.put(state.seen_nonces, nonce)}}
    end
  end

  def handle_call({:sign, signal}, _from, state) do
    result = Crypto.sign(signal, state.private_key, state.public_key)
    {:reply, result, state}
  end
end
