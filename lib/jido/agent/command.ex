defmodule Jido.Agent.Command do
  @moduledoc """
  The input value passed through the Agent Plugin chain.

  A Plugin can inspect the Agent and can prepare the Signal or caller context.
  It cannot replace the Agent value or change executable output.
  """

  alias Jido.Error

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

  @doc "Returns the Zoi schema for an Agent command."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates one validated Agent command."
  @spec new(Jido.Agent.t(), Jido.Signal.t(), map()) ::
          {:ok, t()} | {:error, Exception.t()}
  def new(agent, signal, context \\ %{}) do
    validate(%__MODULE__{agent: agent, signal: signal, context: context})
  end

  @doc "Validates one Agent command."
  @spec validate(term()) :: {:ok, t()} | {:error, Exception.t()}
  def validate(%__MODULE__{} = command) do
    cond do
      not agent?(command.agent) ->
        invalid("Agent command must contain a Jido.Agent", %{agent: command.agent})

      not signal?(command.signal) ->
        invalid("Agent command must contain a Jido.Signal", %{signal: command.signal})

      not is_map(command.context) or is_struct(command.context) ->
        invalid("Agent command context must be a map", %{context: command.context})

      true ->
        {:ok, command}
    end
  end

  def validate(value), do: invalid("Expected a Jido.Agent.Command value", %{value: value})

  @doc false
  @spec normalize_context(term()) :: {:ok, map()} | {:error, Exception.t()}
  def normalize_context(nil), do: {:ok, %{}}

  def normalize_context(context)
      when is_map(context) and not is_struct(context),
      do: {:ok, context}

  def normalize_context(context) when is_list(context) do
    if Keyword.keyword?(context) do
      {:ok, Map.new(context)}
    else
      invalid("Agent caller context must be a map or keyword list", %{context: context})
    end
  end

  def normalize_context(context) do
    invalid("Agent caller context must be a map or keyword list", %{context: context})
  end

  defp agent?(%{__struct__: Jido.Agent}), do: true
  defp agent?(_value), do: false

  defp signal?(%{__struct__: Jido.Signal}), do: true
  defp signal?(_value), do: false

  defp invalid(message, details) do
    {:error, Error.validation_error(message, kind: :config, details: details)}
  end
end
