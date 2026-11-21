defmodule Jido.BehaviorTree.Status do
  @moduledoc """
  Defines the status types returned by behavior tree nodes.

  Every node in a behavior tree returns one of three possible statuses:
  - `:success` - The node completed successfully
  - `:failure` - The node failed to complete
  - `:running` - The node is still executing and needs more ticks

  Additional error status is provided for exceptional cases:
  - `{:error, reason}` - An unexpected error occurred during execution
  """

  @type t :: :success | :failure | :running | {:error, term()}

  @doc """
  Returns true if the status indicates success.

  ## Examples

      iex> Jido.BehaviorTree.Status.success?(:success)
      true

      iex> Jido.BehaviorTree.Status.success?(:failure)
      false

  """
  @spec success?(t()) :: boolean()
  def success?(:success), do: true
  def success?(_), do: false

  @doc """
  Returns true if the status indicates failure.

  ## Examples

      iex> Jido.BehaviorTree.Status.failure?(:failure)
      true

      iex> Jido.BehaviorTree.Status.failure?(:success)
      false

  """
  @spec failure?(t()) :: boolean()
  def failure?(:failure), do: true
  def failure?({:error, _}), do: true
  def failure?(_), do: false

  @doc """
  Returns true if the status indicates the node is still running.

  ## Examples

      iex> Jido.BehaviorTree.Status.running?(:running)
      true

      iex> Jido.BehaviorTree.Status.running?(:success)
      false

  """
  @spec running?(t()) :: boolean()
  def running?(:running), do: true
  def running?(_), do: false

  @doc """
  Returns true if the status indicates an error occurred.

  ## Examples

      iex> Jido.BehaviorTree.Status.error?({:error, "something went wrong"})
      true

      iex> Jido.BehaviorTree.Status.error?(:failure)
      false

  """
  @spec error?(t()) :: boolean()
  def error?({:error, _}), do: true
  def error?(_), do: false

  @doc """
  Returns true if the status indicates the node has completed (success or failure).

  ## Examples

      iex> Jido.BehaviorTree.Status.completed?(:success)
      true

      iex> Jido.BehaviorTree.Status.completed?(:failure)
      true

      iex> Jido.BehaviorTree.Status.completed?(:running)
      false

  """
  @spec completed?(t()) :: boolean()
  def completed?(status) do
    success?(status) or failure?(status)
  end

  @doc """
  Inverts the status (success becomes failure, failure becomes success).
  Running and error statuses are unchanged.

  ## Examples

      iex> Jido.BehaviorTree.Status.invert(:success)
      :failure

      iex> Jido.BehaviorTree.Status.invert(:failure)
      :success

      iex> Jido.BehaviorTree.Status.invert(:running)
      :running

  """
  @spec invert(t()) :: t()
  def invert(:success), do: :failure
  def invert(:failure), do: :success
  def invert(status), do: status

  @doc """
  Converts a Jido Action result to a behavior tree status.

  ## Examples

      iex> Jido.BehaviorTree.Status.from_action_result({:ok, %{result: "success"}})
      :success

      iex> Jido.BehaviorTree.Status.from_action_result({:error, "failed"})
      {:error, "failed"}

  """
  @spec from_action_result({:ok, term()} | {:error, term()}) :: t()
  def from_action_result({:ok, _result}), do: :success
  def from_action_result({:error, reason}), do: {:error, reason}

  @doc """
  Converts a boolean to a behavior tree status.

  ## Examples

      iex> Jido.BehaviorTree.Status.from_boolean(true)
      :success

      iex> Jido.BehaviorTree.Status.from_boolean(false)
      :failure

  """
  @spec from_boolean(boolean()) :: :success | :failure
  def from_boolean(true), do: :success
  def from_boolean(false), do: :failure
end
