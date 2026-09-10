defmodule Jido.Agent.Command do
  @moduledoc """
  The live Agent Server admission envelope.

  An Agent Server Plugin can inspect the Agent and can change the effective
  Signal or caller context. It cannot replace the Agent value. Direct
  `Jido.Agent.cmd/3` evaluation does not allocate a Command.
  """

  alias Jido.Agent
  alias Jido.Error
  alias Jido.Signal
  alias Jido.Signal.Context, as: SignalContext

  @schema Zoi.struct(
            __MODULE__,
            %{
              agent: Zoi.any(description: "Current immutable Agent value"),
              signal: Zoi.any(description: "Signal for this command"),
              context: Zoi.map(description: "Caller execution context") |> Zoi.default(%{})
            }
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the data schema for an Agent command."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates one validated Agent command."
  @spec new(Jido.Agent.instance(), Jido.Signal.t(), map()) ::
          {:ok, t()} | {:error, Exception.t()}
  def new(agent, signal, context \\ %{}) do
    validate(%__MODULE__{agent: agent, signal: signal, context: context})
  end

  @doc false
  @spec new_trusted_agent(Jido.Agent.instance(), Jido.Signal.t(), map()) ::
          {:ok, t()} | {:error, Exception.t()}
  def new_trusted_agent(%Agent{} = agent, signal, context) do
    with {:ok, signal} <- normalize_signal(signal),
         :ok <- validate_context(context) do
      {:ok, %__MODULE__{agent: agent, signal: signal, context: context}}
    end
  end

  @doc "Validates one Agent command."
  @spec validate(term()) :: {:ok, t()} | {:error, Exception.t()}
  def validate(%__MODULE__{} = command) do
    with {:ok, agent} <- Agent.validate_instance(command.agent),
         {:ok, signal} <- normalize_signal(command.signal),
         :ok <- validate_context(command.context) do
      {:ok, %{command | agent: agent, signal: signal}}
    end
  end

  def validate(value), do: invalid("Expected a Jido.Agent.Command value", %{value: value})

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

  defp validate_context(context) when is_map(context) and not is_struct(context), do: :ok

  defp validate_context(context) do
    invalid("Agent command context must be a map", %{context: context})
  end

  defp invalid(message, details) do
    {:error, Error.validation_error(message, kind: :config, details: details)}
  end
end
