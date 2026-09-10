defmodule Jido.Agent.Command do
  @moduledoc """
  The live Agent Server admission envelope.

  Agent Plugin preparation stores package-owned values in the `prepared` input
  slot. Agent Server Plugin admission can reject the Command or fill only its
  package `runtime` slot. Plugins cannot change the Agent, Signal, caller
  context, or the other facet's input.
  Direct `Jido.Agent.cmd/3` evaluation does not allocate a Command.
  """

  alias Jido.Agent
  alias Jido.Error
  alias Jido.Plugin.Input
  alias Jido.Signal
  alias Jido.Signal.Context, as: SignalContext

  @type t :: %__MODULE__{
          agent: Agent.instance(),
          signal: Signal.t(),
          context: map(),
          plugin_inputs: %{optional(module()) => Input.t()}
        }

  @enforce_keys [:agent, :signal]
  defstruct [:agent, :signal, context: %{}, plugin_inputs: %{}]

  @doc "Creates one validated Agent command."
  @spec new(Jido.Agent.instance(), Jido.Signal.t(), map()) ::
          {:ok, t()} | {:error, Exception.t()}
  def new(agent, signal, context \\ %{}) do
    validate(%__MODULE__{
      agent: agent,
      signal: signal,
      context: context,
      plugin_inputs: %{}
    })
  end

  @doc false
  @spec new_trusted_agent(Jido.Agent.instance(), Jido.Signal.t(), map()) ::
          {:ok, t()} | {:error, Exception.t()}
  def new_trusted_agent(%Agent{} = agent, signal, context) do
    with {:ok, signal} <- normalize_signal(signal),
         :ok <- validate_caller_context(context) do
      {:ok, %__MODULE__{agent: agent, signal: signal, context: context, plugin_inputs: %{}}}
    end
  end

  @doc "Validates one Agent command."
  @spec validate(term()) :: {:ok, t()} | {:error, Exception.t()}
  def validate(%__MODULE__{} = command) do
    with {:ok, agent} <- Agent.validate_instance(command.agent),
         {:ok, signal} <- normalize_signal(command.signal),
         :ok <- validate_caller_context(command.context),
         :ok <- validate_plugin_inputs(command.plugin_inputs) do
      {:ok, %{command | agent: agent, signal: signal}}
    end
  end

  def validate(value), do: invalid("Expected a Jido.Agent.Command value", %{value: value})

  @doc false
  @spec put_plugin_input(t(), module(), term()) :: t()
  def put_plugin_input(%__MODULE__{} = command, plugin, input)
      when is_atom(plugin) and not is_nil(plugin) do
    put_plugin_runtime_input(command, plugin, input)
  end

  @doc false
  @spec put_plugin_runtime_input(t(), module(), term()) :: t()
  def put_plugin_runtime_input(%__MODULE__{} = command, plugin, input)
      when is_atom(plugin) and not is_nil(plugin) do
    package_input = command.plugin_inputs |> Map.get(plugin, %Input{}) |> Input.put_runtime(input)
    %{command | plugin_inputs: Map.put(command.plugin_inputs, plugin, package_input)}
  end

  @doc false
  @spec normalize_context(term()) :: {:ok, map()} | {:error, Exception.t()}
  def normalize_context(nil), do: {:ok, %{}}

  def normalize_context(context) do
    case Jido.Agent.Authoring.to_attrs(context) do
      {:ok, context} -> {:ok, context}
      :error -> invalid("Agent caller context must be a map or keyword list", %{context: context})
    end
  end

  @doc false
  @spec normalize_signal(term()) :: {:ok, Signal.t()} | {:error, Exception.t()}
  def normalize_signal(%Signal{} = signal) do
    type = signal.type
    input = if is_binary(type), do: signal, else: %{signal | type: "jido.validation"}

    with {:ok, signal} <- Zoi.parse(Signal.schema(), input),
         {:ok, extensions} <- SignalContext.normalize(signal.extensions) do
      {:ok, %{signal | type: type, extensions: extensions}}
    else
      {:error, issues} -> invalid("Agent command Signal is invalid", %{issues: issues})
    end
  end

  def normalize_signal(value) do
    invalid("Agent command must contain a Jido.Signal", %{signal: value})
  end

  @doc false
  @spec validate_caller_context(term()) :: :ok | {:error, Exception.t()}
  def validate_caller_context(context) when is_map(context) and not is_struct(context) do
    reserved =
      Enum.filter([:agent_id, :agent_state, :signal, :plugin_inputs], &Map.has_key?(context, &1))

    if reserved == [],
      do: :ok,
      else: invalid("Agent command context contains reserved keys", %{keys: reserved})
  end

  def validate_caller_context(context) do
    invalid("Agent command context must be a map", %{context: context})
  end

  defp validate_plugin_inputs(inputs) when is_map(inputs) and not is_struct(inputs) do
    invalid_entry =
      Enum.find(inputs, fn
        {key, %Input{}} -> not is_atom(key) or is_nil(key)
        {_key, _input} -> true
      end)

    case invalid_entry do
      nil ->
        :ok

      {key, %Input{}} ->
        invalid("Agent command Plugin input key must be a module", %{key: key})

      {key, input} ->
        invalid("Agent command Plugin input must use Jido.Plugin.Input", %{
          key: key,
          input: input
        })
    end
  end

  defp validate_plugin_inputs(inputs) do
    invalid("Agent command Plugin inputs must be a map", %{plugin_inputs: inputs})
  end

  defp invalid(message, details) do
    {:error, Error.validation_error(message, kind: :config, details: details)}
  end
end
