defmodule Jido.Agent.Turn do
  @moduledoc """
  A prepared executable turn for one Agent Signal.

  The executable can be an Action, a Flow module, or a `Jido.Flow` value.
  `Jido.AgentServer` owns the execution options and adds the current Signal
  and Agent state to the execution context.

  `source_signal` is the unchanged Signal that selected the Turn. It can be
  `nil` only while an application callback constructs a Turn. The evaluator
  binds and validates the source Signal before executable work starts.

  The Server keeps runtime progress in a private active-turn record and creates
  one `Jido.Agent.Turn.Outcome` at the terminal runtime boundary.
  """

  alias Jido.Error

  @schema Zoi.struct(
            __MODULE__,
            %{
              executable: Zoi.any(description: "Action or Flow executable target"),
              input: Zoi.any(description: "Executable input") |> Zoi.default(%{}),
              source_signal:
                Zoi.struct(Jido.Signal, description: "Unchanged source Signal")
                |> Zoi.nullable()
                |> Zoi.optional()
            }
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the data schema for a prepared Agent Turn."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates and validates one Turn."
  @spec new(term(), term()) :: {:ok, t()} | {:error, Exception.t()}
  def new(executable, input \\ %{}) do
    validate(%__MODULE__{executable: executable, input: input})
  end

  @doc "Creates and validates one Turn for an unchanged source Signal."
  @spec new(term(), term(), Jido.Signal.t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(executable, input, %Jido.Signal{} = source_signal) do
    validate(%__MODULE__{
      executable: executable,
      input: input,
      source_signal: source_signal
    })
  end

  @doc "Creates one Turn or raises its validation error."
  @spec new!(term(), term()) :: t() | no_return()
  def new!(executable, input \\ %{}) do
    case new(executable, input) do
      {:ok, turn} -> turn
      {:error, error} -> raise error
    end
  end

  @doc "Creates one Turn for an unchanged source Signal or raises its validation error."
  @spec new!(term(), term(), Jido.Signal.t()) :: t() | no_return()
  def new!(executable, input, %Jido.Signal{} = source_signal) do
    case new(executable, input, source_signal) do
      {:ok, turn} -> turn
      {:error, error} -> raise error
    end
  end

  @doc false
  @spec bind_source(t(), Jido.Signal.t()) :: {:ok, t()} | {:error, Exception.t()}
  def bind_source(%__MODULE__{source_signal: nil} = turn, %Jido.Signal{} = source_signal),
    do: {:ok, %{turn | source_signal: source_signal}}

  def bind_source(%__MODULE__{source_signal: source_signal} = turn, source_signal),
    do: {:ok, turn}

  def bind_source(
        %__MODULE__{source_signal: %Jido.Signal{} = turn_signal},
        %Jido.Signal{} = source_signal
      ) do
    {:error,
     Error.validation_error("Agent Turn source Signal does not match the received Signal",
       field: :source_signal,
       details: %{
         expected_signal_id: source_signal.id,
         turn_signal_id: turn_signal.id
       }
     )}
  end

  def bind_source(%__MODULE__{source_signal: value}, %Jido.Signal{}),
    do: validate_source_signal(value)

  @doc "Validates one Agent Turn."
  @spec validate(term()) :: {:ok, t()} | {:error, Exception.t()}
  def validate(%__MODULE__{} = turn) do
    with :ok <- validate_plan(turn),
         :ok <- validate_source_signal(turn.source_signal) do
      {:ok, turn}
    end
  end

  def validate(value) do
    {:error,
     Error.validation_error("Expected a Jido.Agent.Turn value",
       kind: :input,
       subject: __MODULE__,
       details: %{value: value}
     )}
  end

  @doc false
  @spec selected(term(), term(), Jido.Signal.t()) :: {:ok, t()} | {:error, Exception.t()}
  def selected(executable, input, %Jido.Signal{} = source_signal) do
    turn = %__MODULE__{executable: executable, input: input, source_signal: source_signal}

    with :ok <- validate_plan(turn), do: {:ok, turn}
  end

  @doc false
  @spec validate_selected(t()) :: {:ok, t()} | {:error, Exception.t()}
  def validate_selected(%__MODULE__{source_signal: %Jido.Signal{}} = turn) do
    with :ok <- validate_plan(turn), do: {:ok, turn}
  end

  def validate_selected(value) do
    {:error,
     Error.validation_error("Expected a selected Jido.Agent.Turn value",
       kind: :input,
       subject: __MODULE__,
       details: %{value: value}
     )}
  end

  defp validate_plan(%__MODULE__{} = turn) do
    with :ok <- Jido.Executable.validate(turn.executable),
         :ok <- validate_data(turn.input, :input),
         do: :ok
  end

  defp validate_data(value, _field) when is_map(value) or is_nil(value),
    do: :ok

  defp validate_data(value, field) when is_list(value) do
    if Keyword.keyword?(value), do: :ok, else: invalid_data(value, field)
  end

  defp validate_data(value, field), do: invalid_data(value, field)

  defp invalid_data(value, field) do
    {:error,
     Error.validation_error("Agent Turn #{field} must be a map, keyword list, or nil",
       field: field,
       details: %{value: value}
     )}
  end

  defp validate_source_signal(nil), do: :ok

  defp validate_source_signal(%Jido.Signal{} = signal) do
    case Zoi.parse(Jido.Signal.schema(), signal) do
      {:ok, %Jido.Signal{}} ->
        :ok

      {:error, issues} ->
        {:error,
         Error.validation_error("Agent Turn source_signal is invalid",
           field: :source_signal,
           details: %{issues: issues}
         )}
    end
  end

  defp validate_source_signal(value) do
    {:error,
     Error.validation_error("Agent Turn source_signal must be a Jido.Signal or nil",
       field: :source_signal,
       details: %{value: value}
     )}
  end
end
