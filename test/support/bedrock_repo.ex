defmodule JidoTest.BedrockRepo do
  @moduledoc false

  use Agent

  @transaction_values {__MODULE__, :transaction_values}

  def start_link(_opts) do
    Agent.start_link(fn -> initial_state() end, name: __MODULE__)
  end

  def __cluster__, do: __MODULE__

  def reset do
    Agent.update(__MODULE__, fn _state -> initial_state() end)
  end

  def fail_next(mode) do
    Agent.update(__MODULE__, &%{&1 | next_mode: mode})
  end

  def transaction_options do
    Agent.get(__MODULE__, &Enum.reverse(&1.transaction_options))
  end

  def values do
    Agent.get(__MODULE__, & &1.values)
  end

  def transact(fun, opts) do
    mode =
      Agent.get_and_update(__MODULE__, fn state ->
        {state.next_mode,
         %{state | next_mode: :normal, transaction_options: [opts | state.transaction_options]}}
      end)

    case mode do
      :normal -> run_transaction(fun)
      {:return, result} -> result
      {:raise, message} -> raise message
      {:after_commit, result} -> run_transaction(fun, fn _transaction_result -> result end)
      {:after_commit_raise, message} -> run_transaction(fun, fn _ -> raise message end)
    end
  end

  def get(key), do: Map.get(transaction_values!(), key)

  def put(key, value) do
    update_transaction_values(&Map.put(&1, key, value))
    :ok
  end

  def clear(key) do
    update_transaction_values(&Map.delete(&1, key))
    :ok
  end

  defp run_transaction(fun, result_fun \\ &Function.identity/1) do
    :global.trans(
      {{__MODULE__, :transaction}, self()},
      fn ->
        initial = Agent.get(__MODULE__, & &1.values)
        Process.put(@transaction_values, initial)

        try do
          result = fun.()
          values = transaction_values!()
          Agent.update(__MODULE__, &%{&1 | values: values})
          result_fun.(result)
        after
          Process.delete(@transaction_values)
        end
      end,
      [node()]
    )
  end

  defp transaction_values! do
    Process.get(@transaction_values) || raise "no active test transaction"
  end

  defp update_transaction_values(fun) do
    Process.put(@transaction_values, fun.(transaction_values!()))
  end

  defp initial_state do
    %{next_mode: :normal, transaction_options: [], values: %{}}
  end
end
