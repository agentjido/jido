defmodule Jido.Exec.Chain do
  @moduledoc """
  Provides functionality to chain multiple Jido Execs together with interruption support.

  This module allows for sequential execution of actions, where the output
  of one action becomes the input for the next action in the chain.
  Execution can be interrupted between actions using an interruption check function.

  ## Examples

      iex> interrupt_check = fn -> System.monotonic_time(:millisecond) > @deadline end
      iex> Jido.Exec.Chain.chain([AddOne, MultiplyByTwo], %{value: 5}, interrupt_check: interrupt_check)
      {:ok, %{value: 12}}

      # When interrupted:
      iex> Jido.Exec.Chain.chain([AddOne, MultiplyByTwo], %{value: 5}, interrupt_check: fn -> true end)
      {:interrupted, %{value: 6}}
  """

  require Logger

  alias Jido.Error
  alias Jido.Exec

  require OK

  @type chain_action :: module() | {module(), keyword()}
  @type chain_result :: {:ok, map()} | {:error, Error.t()} | {:interrupted, map()} | Task.t()
  @type interrupt_check :: (-> boolean())

  @doc """
  Executes a chain of actions sequentially with optional interruption support.

  ## Parameters

  - `actions`: A list of actions to be executed in order. Each action
    can be a module (the action module) or a tuple of `{action_module, options}`.
  - `initial_params`: A map of initial parameters to be passed to the first action.
  - `opts`: Additional options for the chain execution.

  ## Options

  - `:async` - When set to `true`, the chain will be executed asynchronously (default: `false`).
  - `:context` - A map of context data to be passed to each action.
  - `:interrupt_check` - A function that returns boolean, called between actions to check if chain should be interrupted.

  ## Returns

  - `{:ok, result}` where `result` is the final output of the chain.
  - `{:error, error}` if any action in the chain fails.
  - `{:interrupted, result}` if the chain was interrupted, containing the last successful result.
  - `Task.t()` if the `:async` option is set to `true`.
  """
  @spec chain([chain_action()], map(), keyword()) :: chain_result()
  def chain(actions, initial_params \\ %{}, opts \\ []) do
    async = Keyword.get(opts, :async, false)
    context = Keyword.get(opts, :context, %{})
    interrupt_check = Keyword.get(opts, :interrupt_check)
    opts = Keyword.drop(opts, [:async, :context, :interrupt_check])

    chain_fun = fn ->
      Enum.reduce_while(actions, {:ok, initial_params}, fn
        action, {:ok, params} = _acc ->
          if should_interrupt?(interrupt_check) do
            Logger.info("Chain interrupted before action: #{inspect(action)}")
            {:halt, {:interrupted, params}}
          else
            process_action(action, params, context, opts)
          end
      end)
    end

    if async, do: Task.async(chain_fun), else: chain_fun.()
  end

  @spec should_interrupt?(interrupt_check | nil) :: boolean()
  defp should_interrupt?(nil), do: false
  defp should_interrupt?(check) when is_function(check, 0), do: check.()

  @spec process_action(chain_action(), map(), map(), keyword()) ::
          {:cont, OK.t()} | {:halt, chain_result()}
  defp process_action(action, params, context, opts) when is_atom(action) do
    run_action(action, params, context, opts)
  end

  @spec process_action({module(), keyword()} | {module(), map()}, map(), map(), keyword()) ::
          {:cont, OK.t()} | {:halt, chain_result()}
  defp process_action({action, action_opts}, params, context, opts)
       when is_atom(action) and (is_list(action_opts) or is_map(action_opts)) do
    case validate_action_params(action_opts) do
      {:ok, action_params} ->
        merged_params = Map.merge(params, action_params)
        run_action(action, merged_params, context, opts)

      {:error, error} ->
        {:halt, {:error, error}}
    end
  end

  @spec process_action(any(), map(), map(), keyword()) :: {:halt, {:error, Error.t()}}
  defp process_action(invalid_action, _params, _context, _opts) do
    {:halt, {:error, Error.bad_request("Invalid chain action", %{action: invalid_action})}}
  end

  @spec validate_action_params(keyword() | map()) :: {:ok, map()} | {:error, Error.t()}
  defp validate_action_params(opts) when is_list(opts) do
    if Enum.all?(opts, fn {k, _v} -> is_atom(k) end) do
      {:ok, Map.new(opts)}
    else
      {:error, Error.bad_request("Exec parameters must use atom keys")}
    end
  end

  defp validate_action_params(opts) when is_map(opts) do
    if Enum.all?(Map.keys(opts), &is_atom/1) do
      {:ok, opts}
    else
      {:error, Error.bad_request("Exec parameters must use atom keys")}
    end
  end

  @spec run_action(module(), map(), map(), keyword()) ::
          {:cont, OK.t()} | {:halt, chain_result()}
  defp run_action(action, params, context, opts) do
    case Exec.run(action, params, context, opts) do
      OK.success(result) when is_map(result) ->
        {:cont, OK.success(Map.merge(params, result))}

      OK.success(result) ->
        {:cont, OK.success(Map.put(params, :result, result))}

      OK.failure(error) ->
        Logger.warning("Exec in chain failed: #{inspect(action)} #{inspect(error)}")
        {:halt, OK.failure(error)}
    end
  end
end
