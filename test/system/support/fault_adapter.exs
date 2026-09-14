defmodule JidoTest.System.FaultAdapter do
  @moduledoc false
  @behaviour Jido.Persistence.Adapter

  def arm(control, fault), do: sequence(control, [fault])

  def sequence(control, faults) when is_list(faults),
    do: Agent.update(control, fn _ -> faults end)

  def remaining(control), do: Agent.get(control, & &1)

  @impl true
  def get(key, opts) do
    result = delegate(:get, [key], opts)

    case take(opts, :read) do
      {:after_read, observer} ->
        monitor = Process.monitor(observer)
        send(observer, {:record_read, self(), visible_read(result)})

        receive do
          :release_read ->
            Process.demonitor(monitor, [:flush])
            result

          {:DOWN, ^monitor, :process, ^observer, _reason} ->
            {:error, :test_owner_down}
        end

      :pass ->
        result
    end
  end

  @impl true
  def put(key, value, opts), do: delegate(:put, [key, value], opts)
  @impl true
  def delete(key, opts), do: delegate(:delete, [key], opts)

  @impl true
  def compare_and_swap(key, expected, value, opts) do
    revision = :erlang.binary_to_term(value, [:safe]).revision

    case take(opts, revision) do
      :reject ->
        {:error, {:rejected, :system_fault}}

      :lost_reply ->
        :ok = delegate(:compare_and_swap, [key, expected, value], opts)
        {:error, {:indeterminate, :system_lost_reply}}

      {stage, observer} when stage in [:before_write, :after_write] ->
        monitor = Process.monitor(observer)

        result =
          if stage == :after_write, do: delegate(:compare_and_swap, [key, expected, value], opts)

        send(observer, {:checkpoint_barrier, stage, self()})

        receive do
          :release_checkpoint ->
            Process.demonitor(monitor, [:flush])

            if stage == :before_write,
              do: delegate(:compare_and_swap, [key, expected, value], opts),
              else: result

          {:DOWN, ^monitor, :process, ^observer, _reason} ->
            if stage == :before_write,
              do: {:error, {:rejected, :test_owner_down}},
              else: {:error, {:indeterminate, :test_owner_down}}
        end

      :pass ->
        delegate(:compare_and_swap, [key, expected, value], opts)
    end
  end

  defp take(opts, boundary) do
    Agent.get_and_update(Keyword.fetch!(opts, :control), fn
      [{^boundary, mode} | rest] -> {mode, rest}
      other -> {:pass, other}
    end)
  end

  defp delegate(function, args, opts) do
    {adapter, adapter_opts} = Keyword.fetch!(opts, :store)
    apply(adapter, function, args ++ [adapter_opts])
  end

  defp visible_read({:ok, bytes, _token}), do: {:ok, bytes}
  defp visible_read(result), do: result
end
