defmodule Jido.Flow.Ref do
  @moduledoc "A portable reference in a canonical Flow definition."

  alias Jido.Authoring.Config
  alias Jido.Flow.Error

  @type source ::
          :input
          | :context
          | :result
          | :item
          | :item_index
          | :accumulator
          | :state
          | :iteration_index
          | :body_result
  @type scope ::
          :any
          | :flow
          | :map
          | :reduce
          | :iterate_params
          | :iterate_condition
          | :iterate_update
  @type path :: [atom() | String.t() | non_neg_integer()]
  @type t :: %__MODULE__{
          source: source(),
          step: String.t() | nil,
          path: path()
        }

  @sources [
    :input,
    :context,
    :result,
    :item,
    :item_index,
    :accumulator,
    :state,
    :iteration_index,
    :body_result
  ]

  @scoped_sources %{
    item: [:map, :reduce, :any],
    item_index: [:map, :reduce, :any],
    accumulator: [:reduce, :any],
    state: [:iterate_params, :iterate_condition, :iterate_update, :any],
    iteration_index: [:iterate_params, :iterate_condition, :iterate_update, :any],
    body_result: [:iterate_update, :any]
  }

  @enforce_keys [:source]
  defstruct source: nil, step: nil, path: []

  @doc false
  @spec sources() :: [source()]
  def sources, do: @sources

  @doc "Builds a Flow input reference."
  @spec input(term()) :: t()
  def input(path \\ nil), do: ref(:input, nil, path)

  @doc "Builds a runtime context reference."
  @spec context(term()) :: t()
  def context(path \\ nil), do: ref(:context, nil, path)

  @doc "Builds a named Flow form result reference."
  @spec result(atom() | String.t(), term()) :: t()
  def result(step, path \\ nil), do: ref(:result, normalize_step!(step), path)

  @doc "Builds a reference to the current collection item."
  @spec item(term()) :: t()
  def item(path \\ nil), do: ref(:item, nil, path)

  @doc "Builds a reference to the zero-based current collection item index."
  @spec item_index() :: t()
  def item_index, do: ref(:item_index, nil, nil)

  @doc "Builds a reference to the current Reduce accumulator."
  @spec accumulator(term()) :: t()
  def accumulator(path \\ nil), do: ref(:accumulator, nil, path)

  @doc "Builds a reference to the current Iterate state."
  @spec state(term()) :: t()
  def state(path \\ nil), do: ref(:state, nil, path)

  @doc "Builds a reference to the zero-based Iterate index."
  @spec iteration_index() :: t()
  def iteration_index, do: ref(:iteration_index, nil, nil)

  @doc "Builds a reference to the latest Iterate body result."
  @spec body_result(term()) :: t()
  def body_result(path \\ nil), do: ref(:body_result, nil, path)

  @doc "Appends a path to a valid reference."
  @spec select(t(), term()) :: t()
  def select(%__MODULE__{} = source, path) do
    selected = %{source | path: source.path ++ normalize_path(path)}

    case validate(selected, :any) do
      :ok -> selected
      {:error, error} -> raise error
    end
  end

  @doc false
  @spec validate(term(), scope()) :: :ok | {:error, Error.InvalidDefinitionError.t()}
  def validate(ref, scope \\ :flow)

  def validate(%__MODULE__{source: source, step: step, path: path} = ref, scope)
      when scope in [
             :flow,
             :map,
             :reduce,
             :iterate_params,
             :iterate_condition,
             :iterate_update,
             :any
           ] do
    with :ok <- validate_shape(source, step, path),
         :ok <- validate_scope(source, scope),
         :ok <- validate_path(path) do
      :ok
    else
      {:error, reason, details} ->
        {:error,
         Error.validation_error(
           "invalid Flow reference",
           Map.merge(%{ref: ref, reason: reason}, details)
         )}
    end
  end

  def validate(ref, scope) do
    {:error, Error.validation_error("invalid Flow reference", %{ref: ref, scope: scope})}
  end

  @doc false
  @spec normalize_path(term()) :: path()
  def normalize_path(nil), do: []
  def normalize_path(path) when is_list(path), do: path
  def normalize_path(path), do: [path]

  defp ref(source, step, path) do
    %__MODULE__{source: source, step: step, path: normalize_path(path)}
  end

  defp normalize_step!(step) when is_atom(step) and step not in [nil, true, false],
    do: step |> Atom.to_string() |> normalize_step!()

  defp normalize_step!(step) when is_binary(step) do
    case Config.validate_name(step, subject: "Flow Step") do
      :ok -> step
      {:error, message} -> raise ArgumentError, message
    end
  end

  defp normalize_step!(step), do: raise(ArgumentError, "invalid Flow Step name: #{inspect(step)}")

  defp validate_shape(:result, step, _path) when is_binary(step) do
    case Config.validate_name(step, subject: "Flow Step") do
      :ok -> :ok
      {:error, _message} -> {:error, :shape, %{source: :result}}
    end
  end

  defp validate_shape(source, nil, []) when source in [:item_index, :iteration_index], do: :ok

  defp validate_shape(source, nil, _path)
       when source in [:input, :context, :item, :accumulator, :state, :body_result],
       do: :ok

  defp validate_shape(source, _step, _path), do: {:error, :shape, %{source: source}}

  defp validate_scope(source, scope) do
    case Map.fetch(@scoped_sources, source) do
      {:ok, allowed} ->
        if scope in allowed, do: :ok, else: {:error, :scope, %{source: source, scope: scope}}

      :error ->
        :ok
    end
  end

  defp validate_path(path) when is_list(path) do
    if List.improper?(path) do
      {:error, :path, %{segment: path}}
    else
      case Enum.find(path, &(not valid_path_segment?(&1))) do
        nil -> :ok
        segment -> {:error, :path, %{segment: segment}}
      end
    end
  end

  defp validate_path(path), do: {:error, :path, %{segment: path}}

  defp valid_path_segment?(segment) do
    (is_atom(segment) and not is_nil(segment)) or
      (is_binary(segment) and String.valid?(segment)) or
      (is_integer(segment) and segment >= 0)
  end
end
