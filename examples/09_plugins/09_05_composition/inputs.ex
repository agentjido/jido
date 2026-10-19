defmodule Jido.Examples.Plugins.Composition.Tenant do
  @moduledoc "Prepares one portable tenant input without changing the Signal."

  use Jido.Plugin, option_keys: [agent: [:subject_prefix]]

  alias Jido.Agent.Plugin.Preparation

  @impl true
  def prepare(%Preparation{signal: signal}, opts) do
    prefix = Keyword.fetch!(opts, :subject_prefix)

    subject = signal.subject

    if is_binary(subject) and String.starts_with?(subject, prefix) do
      case String.replace_prefix(subject, prefix, "") do
        "" -> {:error, :tenant_subject_required}
        tenant -> {:ok, %{tenant: String.downcase(tenant), signal_id: signal.id}}
      end
    else
      {:error, :tenant_subject_required}
    end
  end
end

defmodule Jido.Examples.Plugins.Composition.Authorization do
  @moduledoc "Adds one live authorization input from private runtime state."

  use Jido.Plugin, option_keys: [agent_server: [:tokens]]

  alias Jido.Agent.Plugin.Preparation
  alias Jido.AgentServer.Plugin.Admission
  alias Jido.Examples.Plugins.Composition.AuthorizationRuntime, as: Runtime
  alias Jido.Plugin.Init

  @impl true
  def validate_options(opts) do
    tokens = Keyword.get(opts, :tokens)

    if valid_tokens?(tokens) do
      :ok
    else
      {:error,
       Jido.Error.validation_error("Runtime admission tokens are invalid",
         kind: :config,
         details: %{tokens: tokens}
       )}
    end
  end

  @impl true
  def prepare(%Preparation{signal: signal}, _opts) do
    {:ok, %{token_present?: is_binary(Map.get(signal.data, :token))}}
  end

  @impl true
  def admit(runtime, %Admission{signal: signal}, _opts) do
    with token when is_binary(token) <- Map.get(signal.data, :token),
         {:ok, authorization} <- Runtime.authorize(runtime, token) do
      {:ok, authorization}
    else
      nil -> {:error, :token_required}
      {:error, _reason} = error -> error
    end
  end

  @impl true
  def await_ready(runtime, _opts), do: Runtime.await_ready(runtime)

  @impl true
  def child_spec(%Init{} = init), do: Supervisor.child_spec({Runtime, init}, id: __MODULE__)

  defp valid_tokens?(tokens) when is_list(tokens) and tokens != [] do
    valid_entries? =
      Enum.all?(tokens, fn
        {token, principal} ->
          is_binary(token) and token != "" and is_binary(principal) and principal != ""

        _entry ->
          false
      end)

    if valid_entries? do
      token_names = Enum.map(tokens, fn {token, _principal} -> token end)
      length(token_names) == length(Enum.uniq(token_names))
    else
      false
    end
  end

  defp valid_tokens?(_tokens), do: false
end

defmodule Jido.Examples.Plugins.Composition.AuthorizationRuntime do
  @moduledoc "Owns the private token table used during live admission."
  use GenServer

  alias Jido.Plugin.Init

  def start_link(%Init{} = init), do: GenServer.start_link(__MODULE__, init)
  def await_ready(runtime), do: GenServer.call(runtime, :await_ready)
  def authorize(runtime, token), do: GenServer.call(runtime, {:authorize, token})

  @impl true
  def init(%Init{options: options}), do: {:ok, Map.new(Keyword.fetch!(options, :tokens))}

  @impl true
  def handle_call(:await_ready, _from, tokens), do: {:reply, :ok, tokens}

  def handle_call({:authorize, token}, _from, tokens) do
    case Map.fetch(tokens, token) do
      {:ok, principal} ->
        {:reply, {:ok, %{principal: principal, lease: make_ref()}}, tokens}

      :error ->
        {:reply, {:error, :invalid_token}, tokens}
    end
  end
end
