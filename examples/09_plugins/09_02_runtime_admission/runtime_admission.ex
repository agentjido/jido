defmodule Jido.Examples.Plugins.RuntimeAdmission.Plugin do
  @moduledoc "Adds one live authorization input from private runtime state."

  use Jido.Plugin,
    agent_server: Jido.Examples.Plugins.RuntimeAdmission.Plugin.Server,
    option_keys: [agent_server: [:tokens]]
end

defmodule Jido.Examples.Plugins.RuntimeAdmission.Plugin.Server do
  @moduledoc false
  use Jido.AgentServer.Plugin

  alias Jido.Agent.Command
  alias Jido.Examples.Plugins.RuntimeAdmission.{Plugin, Runtime}
  alias Jido.Plugin.Init

  @impl true
  def admit(runtime, %Command{signal: signal} = command, _opts) do
    with token when is_binary(token) <- Map.get(signal.data, :token),
         {:ok, authorization} <- Runtime.authorize(runtime, token) do
      {:ok, Command.put_plugin_input(command, Plugin, authorization)}
    else
      nil -> {:error, :token_required}
      {:error, _reason} = error -> error
    end
  end

  def child_spec(%Init{} = init), do: Supervisor.child_spec({Runtime, init}, id: __MODULE__)
end

defmodule Jido.Examples.Plugins.RuntimeAdmission.Runtime do
  @moduledoc "Owns the private token table used during live admission."
  use GenServer

  alias Jido.Plugin.Init

  def start_link(%Init{} = init), do: GenServer.start_link(__MODULE__, init)
  def authorize(runtime, token), do: GenServer.call(runtime, {:authorize, token})

  @impl true
  def init(%Init{options: options}), do: {:ok, Map.new(Keyword.fetch!(options, :tokens))}

  @impl true
  def handle_call({:authorize, token}, _from, tokens) do
    case Map.fetch(tokens, token) do
      {:ok, principal} ->
        {:reply, {:ok, %{principal: principal, lease: make_ref()}}, tokens}

      :error ->
        {:reply, {:error, :invalid_token}, tokens}
    end
  end
end

defmodule Jido.Examples.Plugins.RuntimeAdmission.Agent do
  @moduledoc "Requires live Plugin admission before it accepts a command."
  use Jido.Agent, name: "plugin_runtime_admission_agent"

  agent do
    schema Zoi.object(%{
             accepted: Zoi.integer() |> Zoi.default(0),
             principal: Zoi.string() |> Zoi.default("")
           })

    plugin Jido.Examples.Plugins.RuntimeAdmission.Plugin,
      config: [tokens: [{"allow", "operator"}]]
  end

  routes do
    signal_source "/examples/plugins/runtime_admission"

    route "examples.plugins.runtime_admission.accept" do
      action %{token: _token}, schema: Zoi.object(%{token: Zoi.string()}), context: context do
        case Map.fetch(
               context.plugin_inputs,
               Jido.Examples.Plugins.RuntimeAdmission.Plugin
             ) do
          {:ok, %{principal: principal, lease: lease}} when is_reference(lease) ->
            {:ok,
             %{
               context.agent_state
               | accepted: context.agent_state.accepted + 1,
                 principal: principal
             }}

          :error ->
            {:error, :live_runtime_required}
        end
      end
    end
  end
end
