defmodule Jido.Examples.Plugins.SecureSignal.Plugin do
  @moduledoc "Provides decrypted input and encrypts outbound secure data."

  use Jido.Plugin,
    agent_server: Jido.Examples.Plugins.SecureSignal.Plugin.Server
end

defmodule Jido.Examples.Plugins.SecureSignal.Plugin.Server do
  @moduledoc false
  use Jido.AgentServer.Plugin

  alias Jido.AgentServer.Plugin.Admission
  alias Jido.Plugin.{Init, SignalContext}
  alias Jido.Examples.Plugins.SecureSignal.Runtime

  @impl Jido.AgentServer.Plugin
  def admit(runtime, %Admission{signal: %{data: %{"secure" => envelope}} = signal}, _opts),
    do: Runtime.decrypt(runtime, signal, envelope)

  def admit(_runtime, _admission, _opts), do: {:error, :secure_data_required}

  @impl Jido.AgentServer.Plugin
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

  def child_spec(%Init{} = init), do: Supervisor.child_spec({Runtime, init}, id: __MODULE__)
end

defmodule Jido.Examples.Plugins.SecureSignal.Runtime do
  @moduledoc "Owns the symmetric key used by the secure Signal Plugin."
  use GenServer

  alias Jido.Examples.Plugins.Crypto
  alias Jido.Plugin.Init

  def start_link(%Init{} = init), do: GenServer.start_link(__MODULE__, init)

  def decrypt(runtime, signal, envelope),
    do: GenServer.call(runtime, {:decrypt, signal, envelope})

  def encrypt(runtime, signal, plaintext),
    do: GenServer.call(runtime, {:encrypt, signal, plaintext})

  @impl true
  def init(%Init{}), do: {:ok, %{key: Crypto.secure_key()}}

  @impl true
  def handle_call({:decrypt, signal, envelope}, _from, state),
    do: {:reply, Crypto.decrypt(signal, state.key, envelope), state}

  def handle_call({:encrypt, signal, plaintext}, _from, state),
    do: {:reply, {:ok, Crypto.encrypt(signal, state.key, plaintext)}, state}
end
