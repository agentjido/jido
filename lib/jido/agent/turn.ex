defmodule Jido.Agent.Turn do
  alias Jido.Joi

  @moduledoc """
  A prepared executable turn for one Agent Signal.

  A validated Turn always has a Flow executable. An Action supplied as route
  convenience syntax becomes a canonical one-step `Jido.Flow` value. A bound
  Action Instruction becomes a bound Flow Instruction. `Jido.AgentServer`
  owns the execution options and adds the current Signal and Agent state to
  the execution context.

  `execution_mode` separates behavior from host lifecycle. `:managed` runs in
  the live AgentServer execution context. `:durable` uses the durable Flow
  lifecycle when the AgentServer has persistence. The runner keeps Action
  authoring sugar managed and marks an authored Flow as durable.

  `source_signal` is the unchanged Signal that selected the Turn. It can be
  `nil` while a Turn is constructed. The runner binds and validates the source
  Signal before executable work starts.

  `input` accepts a map, keyword list, or `nil`. Constructors preserve the
  supplied value. Before execution, the runner converts keyword lists to maps
  and `nil` to an empty map. The last value for a duplicate keyword key wins.

  The Server keeps runtime progress in a private active-turn record. Its
  `status/1` and `history/1` functions expose terminal summary maps with IDs,
  status, stage, commit state, revisions, directive count, and duration.
  These summaries exclude Signal data, Agent state, and raw errors.
  Post-commit effects have a separate summary in `status/1`.
  """

  alias Jido.Error

  @schema Joi.struct(
            __MODULE__,
            %{
              executable: Joi.any(description: "Flow executable target"),
              execution_mode:
                Joi.enum([:managed, :durable], description: "AgentServer execution lifecycle")
                |> Joi.default(:managed),
              route: Joi.any(description: "Selected authored route") |> Joi.default(nil),
              input: Joi.any(description: "Executable input") |> Joi.default(%{}),
              source_signal:
                Joi.struct(Jido.Signal, description: "Unchanged source Signal")
                |> Joi.nullable()
                |> Joi.optional()
            }
          )

  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.enforce_keys(@schema)
  defstruct Joi.struct_fields(@schema)

  @doc "Returns the data schema for a prepared Agent Turn."
  @spec schema() :: Joi.schema()
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
       kind: :input,
       subject: :source_signal,
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
    with {:ok, turn} <- validate_plan(turn, false),
         :ok <- validate_execution_mode(turn.execution_mode),
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
  @spec validate_selected(t()) :: {:ok, t()} | {:error, Exception.t()}
  def validate_selected(%__MODULE__{source_signal: %Jido.Signal{}} = turn) do
    with {:ok, turn} <- validate_plan(turn, true),
         :ok <- validate_execution_mode(turn.execution_mode) do
      {:ok, turn}
    end
  end

  def validate_selected(value) do
    {:error,
     Error.validation_error("Expected a selected Jido.Agent.Turn value",
       kind: :input,
       subject: __MODULE__,
       details: %{value: value}
     )}
  end

  @doc false
  @spec normalize_input(term()) :: {:ok, map()} | {:error, Exception.t()}
  def normalize_input(nil), do: {:ok, %{}}
  def normalize_input(value) when is_map(value), do: {:ok, value}

  def normalize_input(value) when is_list(value) do
    if Keyword.keyword?(value), do: {:ok, Map.new(value)}, else: invalid_input(value)
  end

  def normalize_input(value), do: invalid_input(value)

  defp validate_plan(%__MODULE__{} = turn, normalize_input?) do
    with {:ok, executable} <- normalize_executable(turn.executable),
         {:ok, input} <- normalize_input(turn.input) do
      input = if normalize_input?, do: input, else: turn.input
      {:ok, %{turn | executable: executable, input: input}}
    end
  end

  defp normalize_executable(executable) do
    with {:ok, instruction} <- Jido.Instruction.resolve(executable),
         :ok <- Jido.Instruction.validate_resolved(instruction) do
      lower_action(executable, instruction)
    end
  end

  defp lower_action(executable, %Jido.Instruction{kind: :flow}), do: {:ok, executable}

  defp lower_action(executable, %Jido.Instruction{kind: :action} = instruction) do
    with {:ok, flow} <- Jido.Flow.from_action(instruction.target) do
      if match?(%Jido.Instruction{}, executable),
        do: {:ok, %{instruction | kind: :flow, target: flow}},
        else: {:ok, flow}
    end
  end

  defp validate_execution_mode(mode) when mode in [:managed, :durable], do: :ok

  defp validate_execution_mode(mode) do
    {:error,
     Error.validation_error("Agent Turn execution_mode must be :managed or :durable",
       kind: :input,
       subject: :execution_mode,
       field: :execution_mode,
       details: %{value: mode}
     )}
  end

  defp invalid_input(value) do
    {:error,
     Error.validation_error("Agent Turn input must be a map, keyword list, or nil",
       kind: :input,
       subject: :input,
       field: :input,
       details: %{value: value}
     )}
  end

  defp validate_source_signal(nil), do: :ok

  defp validate_source_signal(%Jido.Signal{} = signal) do
    case Joi.parse(Jido.Signal.schema(), signal) do
      {:ok, %Jido.Signal{}} ->
        :ok

      {:error, issues} ->
        {:error,
         Error.validation_error("Agent Turn source_signal is invalid",
           kind: :input,
           subject: :source_signal,
           field: :source_signal,
           details: %{issues: issues}
         )}
    end
  end

  defp validate_source_signal(value) do
    {:error,
     Error.validation_error("Agent Turn source_signal must be a Jido.Signal or nil",
       kind: :input,
       subject: :source_signal,
       field: :source_signal,
       details: %{value: value}
     )}
  end
end
