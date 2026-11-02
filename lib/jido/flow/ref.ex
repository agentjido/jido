defmodule Jido.Flow.Ref do
  @moduledoc "A portable reference in a canonical Flow expression."

  alias Jido.Authoring.Config
  alias Jido.Flow.Error

  @type source ::
          :input
          | :context
          | :result
          | :item
          | :item_index
          | :item_id
          | :accumulator
          | :state
          | :iteration_index
          | :body_result
  @type scope ::
          :any
          | :flow
          | :map_collection
          | :map_params
          | :reduce_collection
          | :reduce_initial
          | :reduce_params
          | :iterate_initial
          | :iterate_params
          | :iterate_update
          | :iterate_completion
  @type path :: [atom() | String.t() | non_neg_integer()]

  @sources [
    :input,
    :context,
    :result,
    :item,
    :item_index,
    :item_id,
    :accumulator,
    :state,
    :iteration_index,
    :body_result
  ]

  @doc false
  @spec sources() :: [source()]
  def sources, do: @sources

  @schema Zoi.struct(
            __MODULE__,
            %{
              source:
                Zoi.enum(
                  @sources,
                  description: "Reference source"
                ),
              component: Zoi.string(description: "Result component name") |> Zoi.optional(),
              path: Zoi.list(Zoi.any(), description: "Nested value path") |> Zoi.default([])
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Builds a Flow input reference with a required path."
  @spec input(term()) :: t()
  def input(path), do: ref(:input, nil, path)

  @doc "Builds a runtime context reference."
  @spec context(term()) :: t()
  def context(path \\ nil), do: ref(:context, nil, path)

  @doc "Builds a named component result reference."
  @spec result(atom() | String.t(), term()) :: t()
  def result(component, path \\ nil), do: ref(:result, normalize_component(component), path)

  @doc "Appends a path to a reference after validating its source."
  @spec select(t(), term()) :: t() | no_return()
  def select(%__MODULE__{} = source, path) do
    case validate(source, :any) do
      :ok -> %{source | path: source.path ++ normalize_path(path)}
      {:error, error} -> raise error
    end
  end

  @doc "Builds a Map or Reduce item reference."
  @spec item(term()) :: t()
  def item(path \\ nil), do: ref(:item, nil, path)

  @doc "Builds a collection item index reference."
  @spec item_index() :: t()
  def item_index, do: ref(:item_index)

  @doc "Builds a collection item identifier reference."
  @spec item_id() :: t()
  def item_id, do: ref(:item_id)

  @doc "Builds a Reduce accumulator reference."
  @spec accumulator(term()) :: t()
  def accumulator(path \\ nil), do: ref(:accumulator, nil, path)

  @doc "Builds an Iterate state reference."
  @spec state(term()) :: t()
  def state(path \\ nil), do: ref(:state, nil, path)

  @doc "Builds an Iterate index reference."
  @spec iteration_index() :: t()
  def iteration_index, do: ref(:iteration_index)

  @doc "Builds an Iterate body result reference."
  @spec body_result(term()) :: t()
  def body_result(path \\ nil), do: ref(:body_result, nil, path)

  @doc false
  @spec validate(t(), scope()) :: :ok | {:error, Error.InvalidDefinitionError.t()}
  def validate(ref, scope \\ :flow)

  def validate(%__MODULE__{source: source, component: component, path: path} = ref, scope) do
    with :ok <- validate_shape(source, component, path),
         :ok <- validate_scope(source, scope),
         :ok <- validate_path(path) do
      :ok
    else
      {:error, reason, details} ->
        {:error,
         Error.validation_error(
           "invalid flow ref",
           Map.merge(%{ref: ref, reason: reason}, details)
         )}
    end
  end

  @doc false
  @spec normalize_path(term()) :: path()
  def normalize_path(nil), do: []
  def normalize_path(path) when is_list(path), do: path
  def normalize_path(path), do: [path]

  defp ref(source, component \\ nil, path \\ nil) do
    %__MODULE__{source: source, component: component, path: normalize_path(path)}
  end

  defp normalize_component(component) when is_atom(component) and not is_nil(component),
    do: Atom.to_string(component)

  defp normalize_component(component) when is_binary(component), do: component

  defp validate_shape(:result, component, _path) when is_binary(component) do
    case Config.validate_name(component) do
      :ok -> :ok
      {:error, _message} -> {:error, :shape, %{source: :result}}
    end
  end

  defp validate_shape(source, nil, _path)
       when source in [:input, :context, :item, :accumulator, :state, :body_result],
       do: :ok

  defp validate_shape(source, nil, [])
       when source in [:item_index, :item_id, :iteration_index],
       do: :ok

  defp validate_shape(source, _component, _path), do: {:error, :shape, %{source: source}}

  defp validate_scope(source, _scope) when source in [:input, :context, :result], do: :ok

  defp validate_scope(_source, :any), do: :ok

  defp validate_scope(source, scope)
       when source in [:item, :item_index, :item_id] and scope in [:map_params, :reduce_params],
       do: :ok

  defp validate_scope(:accumulator, :reduce_params), do: :ok

  defp validate_scope(source, scope)
       when source in [:state, :iteration_index, :body_result] and
              scope in [:iterate_params, :iterate_update, :iterate_completion],
       do: :ok

  defp validate_scope(source, scope), do: {:error, :scope, %{source: source, scope: scope}}

  defp validate_path(path) when is_list(path) do
    if List.improper?(path) do
      {:error, :path, %{segment: path}}
    else
      Enum.reduce_while(path, :ok, fn segment, :ok ->
        if valid_path_segment?(segment),
          do: {:cont, :ok},
          else: {:halt, {:error, :path, %{segment: segment}}}
      end)
    end
  end

  defp validate_path(path), do: {:error, :path, %{segment: path}}

  defp valid_path_segment?(segment) do
    (is_atom(segment) and not is_nil(segment)) or
      (is_binary(segment) and String.valid?(segment)) or
      (is_integer(segment) and segment >= 0)
  end
end
