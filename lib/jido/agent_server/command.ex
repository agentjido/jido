defmodule Jido.AgentServer.Command do
  @moduledoc """
  The live AgentServer admission envelope.

  Agent Plugin preparation stores package-owned values in the `prepared` input
  slot. AgentServer Plugin admission can reject the Command or fill only its
  package `runtime` slot. Plugins cannot change the Agent, Signal, caller
  context, or the other facet's input.
  Direct `Jido.Agent.cmd/3` evaluation does not allocate a Command.
  """

  alias Jido.Agent
  alias Jido.Agent.Validation
  alias Jido.Error
  alias Jido.Plugin.Input
  alias Jido.Signal

  @type t :: %__MODULE__{
          agent: Agent.instance(),
          signal: Signal.t(),
          context: map(),
          plugin_inputs: %{optional(module()) => Input.t()}
        }

  @enforce_keys [:agent, :signal]
  defstruct [:agent, :signal, context: %{}, plugin_inputs: %{}]

  @doc "Creates one validated AgentServer command."
  @spec new(Agent.instance(), Signal.t(), map()) :: {:ok, t()} | {:error, Exception.t()}
  def new(agent, signal, context \\ %{}) do
    validate(%__MODULE__{
      agent: agent,
      signal: signal,
      context: context,
      plugin_inputs: %{}
    })
  end

  @doc false
  @spec new_trusted_agent(Agent.instance(), Signal.t(), map()) ::
          {:ok, t()} | {:error, Exception.t()}
  def new_trusted_agent(%Agent{} = agent, signal, context) do
    with {:ok, signal} <- Validation.normalize_signal(signal),
         :ok <- Validation.validate_caller_context(context) do
      {:ok, %__MODULE__{agent: agent, signal: signal, context: context, plugin_inputs: %{}}}
    end
  end

  @doc "Validates one AgentServer command."
  @spec validate(term()) :: {:ok, t()} | {:error, Exception.t()}
  def validate(%__MODULE__{} = command) do
    with {:ok, agent} <- Validation.validate_instance(command.agent),
         {:ok, signal} <- Validation.normalize_signal(command.signal),
         :ok <- Validation.validate_caller_context(command.context),
         :ok <- validate_plugin_inputs(command.plugin_inputs) do
      {:ok, %{command | agent: agent, signal: signal}}
    end
  end

  def validate(value),
    do: invalid("Expected a Jido.AgentServer.Command value", %{value: value})

  @doc false
  @spec put_plugin_runtime_input(t(), module(), term()) :: t()
  def put_plugin_runtime_input(%__MODULE__{} = command, plugin, input)
      when is_atom(plugin) and not is_nil(plugin) do
    package_input = command.plugin_inputs |> Map.get(plugin, %Input{}) |> Input.put_runtime(input)
    %{command | plugin_inputs: Map.put(command.plugin_inputs, plugin, package_input)}
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
        invalid("AgentServer command Plugin input key must be a module", %{key: key})

      {key, input} ->
        invalid("AgentServer command Plugin input must use Jido.Plugin.Input", %{
          key: key,
          input: input
        })
    end
  end

  defp validate_plugin_inputs(inputs),
    do: invalid("AgentServer command Plugin inputs must be a map", %{plugin_inputs: inputs})

  defp invalid(message, details),
    do: {:error, Error.validation_error(message, kind: :config, details: details)}
end
