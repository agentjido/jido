defmodule Jido.Exec.Frame do
  @moduledoc false

  alias Jido.Flow.Error

  @tag :jido_flow_frame
  @nested_tag :jido_nested_flow_frame
  @version 1

  @type t :: {:jido_flow_frame, 1, term(), map(), %{optional(String.t()) => [term()]}}
  @type nested_t :: {:jido_nested_flow_frame, 1, t() | nested_t(), t()}

  @doc false
  @spec new(term()) :: t()
  def new(input), do: {@tag, @version, input, %{}, %{}}

  @doc false
  @spec nest(t() | nested_t(), term()) :: nested_t()
  def nest(parent, input), do: {@nested_tag, @version, parent, new(input)}

  @doc false
  @spec merge(t() | nested_t() | [t() | nested_t()]) ::
          {:ok, t() | nested_t()} | {:error, Exception.t()}
  def merge({@tag, @version, _input, _results, _effects} = frame), do: {:ok, frame}

  def merge({@nested_tag, @version, parent, child} = frame) do
    with {:ok, _parent} <- merge(parent), {:ok, _child} <- merge(child), do: {:ok, frame}
  end

  def merge([first | rest]) do
    with {:ok, first} <- merge(first) do
      Enum.reduce_while(rest, {:ok, first}, fn next, {:ok, current} ->
        case merge_pair(current, next) do
          {:ok, merged} -> {:cont, {:ok, merged}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end
  end

  def merge(value) do
    {:error,
     Error.execution_error("Runic supplied an invalid Flow fact", %{
       reason: :invalid_flow_frame,
       value: value
     })}
  end

  @doc false
  @spec put_result(t() | nested_t(), String.t(), term(), [term()]) :: t() | nested_t()
  def put_result({@tag, @version, input, results, effects}, name, value, requests) do
    {
      @tag,
      @version,
      input,
      Map.put(results, name, value),
      Map.put(effects, name, requests)
    }
  end

  def put_result({@nested_tag, @version, parent, child}, name, value, requests) do
    {@nested_tag, @version, parent, put_result(child, name, value, requests)}
  end

  @doc false
  @spec item_id(term(), non_neg_integer()) :: String.t()
  def item_id(owner_id, index) do
    {owner_id, index}
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc false
  @spec resolver_state(t() | nested_t(), map()) :: map()
  def resolver_state({@tag, @version, input, results, _effects}, context) do
    %{input: input, context: context, results: results}
  end

  def resolver_state({@nested_tag, @version, _parent, child}, context) do
    resolver_state(child, context)
  end

  @doc false
  @spec effects(t() | nested_t(), [String.t()]) :: [term()]
  def effects({@tag, @version, _input, _results, effects}, order) do
    Enum.flat_map(order, &Map.get(effects, &1, []))
  end

  def effects({@nested_tag, @version, _parent, child}, order), do: effects(child, order)

  @doc false
  @spec fetch_result(t() | nested_t(), String.t()) :: {:ok, term()} | :error
  def fetch_result({@tag, @version, _input, results, _effects}, name),
    do: Map.fetch(results, name)

  def fetch_result({@nested_tag, @version, _parent, child}, name),
    do: fetch_result(child, name)

  @doc false
  @spec effects_for(t() | nested_t(), String.t()) :: [term()]
  def effects_for({@tag, @version, _input, _results, effects}, name),
    do: Map.get(effects, name, [])

  def effects_for({@nested_tag, @version, _parent, child}, name),
    do: effects_for(child, name)

  @doc false
  @spec complete_nested(nested_t(), String.t(), term(), [term()]) :: t() | nested_t()
  def complete_nested({@nested_tag, @version, parent, _child}, name, value, requests) do
    put_result(parent, name, value, requests)
  end

  defp merge_pair(
         {@tag, @version, input, left_results, left_effects},
         {@tag, @version, input, right_results, right_effects}
       ) do
    with {:ok, results} <- merge_equal(left_results, right_results, :result),
         {:ok, effects} <- merge_equal(left_effects, right_effects, :effects) do
      {:ok, {@tag, @version, input, results, effects}}
    end
  end

  defp merge_pair(
         {@nested_tag, @version, parent, left_child},
         {@nested_tag, @version, parent, right_child}
       ) do
    with {:ok, child} <- merge_pair(left_child, right_child) do
      {:ok, {@nested_tag, @version, parent, child}}
    end
  end

  defp merge_pair(_left, _right) do
    {:error,
     Error.execution_error("Flow branches do not share one input", %{
       reason: :incompatible_flow_frames
     })}
  end

  defp merge_equal(left, right, kind) do
    Enum.reduce_while(right, {:ok, left}, fn {key, value}, {:ok, merged} ->
      case Map.fetch(merged, key) do
        :error ->
          {:cont, {:ok, Map.put(merged, key, value)}}

        {:ok, ^value} ->
          {:cont, {:ok, merged}}

        {:ok, other} ->
          {:halt,
           {:error,
            Error.execution_error("Flow branches contain conflicting data", %{
              reason: :conflicting_flow_frame,
              kind: kind,
              component: key,
              left: other,
              right: value
            })}}
      end
    end)
  end
end
