defmodule Jido.Agent.Turn do
  @moduledoc """
  A prepared executable turn for one Agent Signal.

  The executable can be an Action, a Flow module, or a `Jido.Flow` value.
  `Jido.AgentServer` owns the execution options and adds the current Signal
  and Agent state to the execution context.

  This struct is the Turn input. The Server keeps its runtime progress in a
  private active-turn record and creates one `Jido.Agent.Turn.Outcome` at the
  terminal runtime boundary.
  """

  alias Jido.Error

  @schema Zoi.struct(
            __MODULE__,
            %{
              executable: Zoi.any(description: "Action or Flow executable target"),
              input: Zoi.any(description: "Executable input") |> Zoi.default(%{})
            }
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for a prepared Agent turn."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(term(), term()) :: {:ok, t()} | {:error, Exception.t()}
  def new(executable, input \\ %{}) do
    validate(%__MODULE__{executable: executable, input: input})
  end

  @spec new!(term(), term()) :: t() | no_return()
  def new!(executable, input \\ %{}) do
    case new(executable, input) do
      {:ok, turn} -> turn
      {:error, error} -> raise error
    end
  end

  @spec validate(t()) :: {:ok, t()} | {:error, Exception.t()}
  def validate(%__MODULE__{} = turn) do
    with :ok <- Jido.Executable.validate(turn.executable),
         :ok <- validate_data(turn.input, :input) do
      {:ok, turn}
    end
  end

  defp validate_data(value, _field) when is_map(value) or is_list(value) or is_nil(value),
    do: :ok

  defp validate_data(value, field) do
    {:error,
     Error.validation_error("Agent Turn #{field} must be a map, keyword list, or nil",
       field: field,
       details: %{value: value}
     )}
  end
end
