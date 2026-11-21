defmodule Jido.BehaviorTree.Blackboard do
  @moduledoc """
  A shared data structure for communication between behavior tree nodes.

  The blackboard pattern allows nodes in a behavior tree to share data
  without tight coupling. Nodes can read from and write to the blackboard
  to coordinate their behavior and share results.

  The blackboard is essentially a map with convenience functions for
  common operations like getting, setting, and updating values.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              data:
                Zoi.map(Zoi.any(), Zoi.any(), description: "Shared data for behavior tree nodes")
                |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for this module"
  def schema, do: @schema

  @doc """
  Creates a new blackboard with optional initial data.

  ## Examples

      iex> bb = Jido.BehaviorTree.Blackboard.new()
      %Jido.BehaviorTree.Blackboard{data: %{}}

      iex> bb = Jido.BehaviorTree.Blackboard.new(%{user_id: 123, status: "active"})
      %Jido.BehaviorTree.Blackboard{data: %{user_id: 123, status: "active"}}

  """
  @spec new(map()) :: t()
  def new(initial_data \\ %{}) do
    %__MODULE__{data: initial_data}
  end

  @doc """
  Gets a value from the blackboard by key.

  ## Examples

      iex> bb = Jido.BehaviorTree.Blackboard.new(%{user_id: 123})
      iex> Jido.BehaviorTree.Blackboard.get(bb, :user_id)
      123

      iex> Jido.BehaviorTree.Blackboard.get(bb, :missing_key, "default")
      "default"

  """
  @spec get(t(), term(), term()) :: term()
  def get(%__MODULE__{data: data}, key, default \\ nil) do
    Map.get(data, key, default)
  end

  @doc """
  Sets a value in the blackboard.

  ## Examples

      iex> bb = Jido.BehaviorTree.Blackboard.new()
      iex> bb = Jido.BehaviorTree.Blackboard.put(bb, :user_id, 123)
      iex> Jido.BehaviorTree.Blackboard.get(bb, :user_id)
      123

  """
  @spec put(t(), term(), term()) :: t()
  def put(%__MODULE__{data: data} = bb, key, value) do
    %{bb | data: Map.put(data, key, value)}
  end

  @doc """
  Updates a value in the blackboard using a function.

  If the key doesn't exist, the initial value is used as input to the function.

  ## Examples

      iex> bb = Jido.BehaviorTree.Blackboard.new(%{counter: 5})
      iex> bb = Jido.BehaviorTree.Blackboard.update(bb, :counter, 0, &(&1 + 1))
      iex> Jido.BehaviorTree.Blackboard.get(bb, :counter)
      6

      iex> bb = Jido.BehaviorTree.Blackboard.new()
      iex> bb = Jido.BehaviorTree.Blackboard.update(bb, :counter, 0, &(&1 + 1))
      iex> Jido.BehaviorTree.Blackboard.get(bb, :counter)
      1

  """
  @spec update(t(), term(), term(), (term() -> term())) :: t()
  def update(%__MODULE__{data: data} = bb, key, initial, fun) do
    current_value = Map.get(data, key, initial)
    new_value = fun.(current_value)
    %{bb | data: Map.put(data, key, new_value)}
  end

  @doc """
  Deletes a key from the blackboard.

  ## Examples

      iex> bb = Jido.BehaviorTree.Blackboard.new(%{user_id: 123, temp: "delete_me"})
      iex> bb = Jido.BehaviorTree.Blackboard.delete(bb, :temp)
      iex> Jido.BehaviorTree.Blackboard.get(bb, :temp)
      nil

  """
  @spec delete(t(), term()) :: t()
  def delete(%__MODULE__{data: data} = bb, key) do
    %{bb | data: Map.delete(data, key)}
  end

  @doc """
  Checks if the blackboard contains a key.

  ## Examples

      iex> bb = Jido.BehaviorTree.Blackboard.new(%{user_id: 123})
      iex> Jido.BehaviorTree.Blackboard.has_key?(bb, :user_id)
      true

      iex> Jido.BehaviorTree.Blackboard.has_key?(bb, :missing)
      false

  """
  @spec has_key?(t(), term()) :: boolean()
  def has_key?(%__MODULE__{data: data}, key) do
    Map.has_key?(data, key)
  end

  @doc """
  Gets all keys from the blackboard.

  ## Examples

      iex> bb = Jido.BehaviorTree.Blackboard.new(%{a: 1, b: 2})
      iex> Jido.BehaviorTree.Blackboard.keys(bb)
      [:a, :b]

  """
  @spec keys(t()) :: [term()]
  def keys(%__MODULE__{data: data}) do
    Map.keys(data)
  end

  @doc """
  Gets all values from the blackboard.

  ## Examples

      iex> bb = Jido.BehaviorTree.Blackboard.new(%{a: 1, b: 2})
      iex> Jido.BehaviorTree.Blackboard.values(bb)
      [1, 2]

  """
  @spec values(t()) :: [term()]
  def values(%__MODULE__{data: data}) do
    Map.values(data)
  end

  @doc """
  Merges another map or blackboard into this blackboard.

  ## Examples

      iex> bb1 = Jido.BehaviorTree.Blackboard.new(%{a: 1, b: 2})
      iex> bb2 = Jido.BehaviorTree.Blackboard.new(%{b: 3, c: 4})
      iex> bb = Jido.BehaviorTree.Blackboard.merge(bb1, bb2)
      iex> Jido.BehaviorTree.Blackboard.get(bb, :b)
      3

  """
  @spec merge(t(), t() | map()) :: t()
  def merge(%__MODULE__{data: data1} = bb, %__MODULE__{data: data2}) do
    %{bb | data: Map.merge(data1, data2)}
  end

  def merge(%__MODULE__{data: data1} = bb, data2) when is_map(data2) do
    %{bb | data: Map.merge(data1, data2)}
  end

  @doc """
  Converts the blackboard to a plain map.

  ## Examples

      iex> bb = Jido.BehaviorTree.Blackboard.new(%{user_id: 123})
      iex> Jido.BehaviorTree.Blackboard.to_map(bb)
      %{user_id: 123}

  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{data: data}) do
    data
  end

  @doc """
  Returns the size (number of keys) in the blackboard.

  ## Examples

      iex> bb = Jido.BehaviorTree.Blackboard.new(%{a: 1, b: 2})
      iex> Jido.BehaviorTree.Blackboard.size(bb)
      2

  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{data: data}) do
    map_size(data)
  end

  @doc """
  Checks if the blackboard is empty.

  ## Examples

      iex> bb = Jido.BehaviorTree.Blackboard.new()
      iex> Jido.BehaviorTree.Blackboard.empty?(bb)
      true

      iex> bb = Jido.BehaviorTree.Blackboard.new(%{a: 1})
      iex> Jido.BehaviorTree.Blackboard.empty?(bb)
      false

  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{data: data}) do
    map_size(data) == 0
  end
end
