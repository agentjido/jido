defmodule Jido.Exec.Closure do
  @moduledoc """
  Provides functionality to create closures around Jido Execs (Actions).

  This module allows for partial application of context and options to actions,
  creating reusable action closures that can be executed with different parameters.
  """

  alias Jido.Error
  alias Jido.Exec

  @type action :: Exec.action()
  @type params :: Exec.params()
  @type context :: Exec.context()
  @type run_opts :: Exec.run_opts()
  @type closure :: (params() -> {:ok, map()} | {:error, Error.t()})

  @doc """
  Creates a closure around a action with pre-applied context and options.

  ## Parameters

  - `action`: The action module to create a closure for.
  - `context`: The context to be applied to the action (default: %{}).
  - `opts`: The options to be applied to the action execution (default: []).

  ## Returns

  A function that takes params and returns the result of running the action.

  ## Examples

      iex> closure = Jido.Exec.Closure.closure(MyAction, %{user_id: 123}, [timeout: 10_000])
      iex> closure.(%{input: "test"})
      {:ok, %{result: "processed test"}}

  """
  @spec closure(action(), context(), run_opts()) :: closure()
  def closure(action, context \\ %{}, opts \\ []) when is_atom(action) and is_list(opts) do
    fn params ->
      Exec.run(action, params, context, opts)
    end
  end

  @doc """
  Creates an async closure around a action with pre-applied context and options.

  ## Parameters

  - `action`: The action module to create an async closure for.
  - `context`: The context to be applied to the action (default: %{}).
  - `opts`: The options to be applied to the action execution (default: []).

  ## Returns

  A function that takes params and returns an async reference.

  ## Examples

      iex> async_closure = Jido.Exec.Closure.async_closure(MyAction, %{user_id: 123}, [timeout: 10_000])
      iex> async_ref = async_closure.(%{input: "test"})
      iex> Jido.Exec.await(async_ref)
      {:ok, %{result: "processed test"}}

  """
  @spec async_closure(action(), context(), run_opts()) :: (params() -> Exec.async_ref())
  def async_closure(action, context \\ %{}, opts \\ []) when is_atom(action) and is_list(opts) do
    fn params ->
      Exec.run_async(action, params, context, opts)
    end
  end
end
