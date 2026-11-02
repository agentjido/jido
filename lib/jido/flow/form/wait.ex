defmodule Jido.Flow.Form.Wait do
  @moduledoc """
  The canonical form for one suspended event or timer selection.

  Await and Timer contain one clause. Selection contains several ordered
  clauses. All three DSL forms normalize to this same canonical form.
  """

  alias Jido.Flow.{Error, Limits, Value}
  alias Jido.Flow.Form.Validation

  require Jido.Authoring.Limits

  @maximum_duration_ms Jido.Authoring.Limits.maximum_duration_ms()

  @form_fields [:type, :clauses]

  @type clause ::
          {:event, String.t(), String.t(), Jido.Flow.Value.t()}
          | {:timer, String.t(), non_neg_integer()}
  @type t :: %__MODULE__{clauses: [clause()]}

  @enforce_keys [:clauses]
  defstruct [:clauses]

  @doc false
  @spec normalize(term()) :: {:ok, t()} | {:error, Exception.t()}
  def normalize(%__MODULE__{} = form), do: build(form.clauses)

  def normalize(%{} = attrs) when not is_struct(attrs) do
    with {:ok, attrs} <-
           Validation.normalize_fields(attrs, @form_fields, "Wait"),
         :ok <- Validation.validate_tag(attrs, :wait, "Wait"),
         {:ok, clauses} <- fetch_clauses(attrs) do
      build(clauses)
    end
  end

  def normalize(value) do
    {:error, Error.validation_error("Wait form must be a map", %{reason: :wait, value: value})}
  end

  defp fetch_clauses(%{clauses: clauses}), do: {:ok, clauses}

  defp fetch_clauses(_attrs) do
    {:error, Error.validation_error("Wait clauses are required", %{reason: :clauses_required})}
  end

  defp build(clauses) when is_list(clauses) do
    cond do
      List.improper?(clauses) ->
        invalid("Wait clauses must be a proper list", :clauses)

      clauses == [] ->
        invalid("Wait must contain at least one clause", :empty_clauses)

      true ->
        with :ok <- Limits.collection(clauses, :clauses), do: normalize_clauses(clauses)
    end
  end

  defp build(_clauses), do: invalid("Wait clauses must be a list", :clauses)

  defp normalize_clauses(clauses) do
    clauses
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], MapSet.new()}, fn {clause, index}, {:ok, result, names} ->
      with {:ok, clause} <- normalize_clause(clause, index),
           name = elem(clause, 1),
           false <- MapSet.member?(names, name) do
        {:cont, {:ok, [clause | result], MapSet.put(names, name)}}
      else
        true -> {:halt, invalid("Wait contains a duplicate clause name", :duplicate_clause)}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, result, _names} -> {:ok, %__MODULE__{clauses: Enum.reverse(result)}}
      error -> error
    end
  end

  defp normalize_clause({:event, name, event, match}, index) do
    with {:ok, name} <-
           Validation.normalize_name(name, "Wait clause", :clause_name, [1]),
         :ok <- validate_event(event, index),
         {:ok, match} <- Value.prepare(match, :flow),
         :ok <- validate_match(match) do
      {:ok, {:event, name, event, match}}
    else
      {:error, error} -> {:error, Error.prefix_path(error, [:clauses, index])}
    end
  end

  defp normalize_clause({:timer, name, delay}, index) do
    with {:ok, name} <-
           Validation.normalize_name(name, "Wait clause", :clause_name, [1]),
         :ok <- validate_delay(delay, index) do
      {:ok, {:timer, name, delay}}
    end
  end

  defp normalize_clause(_clause, index),
    do: invalid("Wait clause is invalid", :clause, path: [:clauses, index])

  defp validate_event(event, _index)
       when is_binary(event) and byte_size(event) > 0,
       do:
         if(String.valid?(event),
           do: :ok,
           else: invalid("Wait event must be valid UTF-8", :event)
         )

  defp validate_event(_event, _index), do: invalid("Wait event must be a string", :event)

  defp validate_match(match) when is_map(match) and not is_struct(match), do: :ok
  defp validate_match(_match), do: invalid("Wait event match must be a map", :match)

  defp validate_delay(delay, _index)
       when is_integer(delay) and delay >= 0 and
              delay <= @maximum_duration_ms,
       do: :ok

  defp validate_delay(_delay, _index) do
    invalid("Wait delay is outside its supported range", :delay,
      maximum_duration_ms: @maximum_duration_ms
    )
  end

  defp invalid(message, reason, details \\ []) do
    {:error, Error.validation_error(message, Map.new([reason: reason] ++ details))}
  end
end
