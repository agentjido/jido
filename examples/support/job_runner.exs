defmodule Jido.Test.Examples.JobRunner.Barrier do
  @moduledoc false

  def run({owner, label}, value) do
    notify(owner, {:job_work, self(), label || value})

    receive do
      :release -> {:ok, Integer.to_string(value * 2)}
      {:finish, result} -> result
    after
      5_000 -> raise "job runner barrier was not released"
    end
  end

  defp notify({:global, name}, message), do: :global.send(name, message)
  defp notify(owner, message), do: send(owner, message)
end

defmodule Jido.Test.Examples.JobRunner do
  @moduledoc false

  alias Jido.Test.Examples.JobRunner.Barrier

  def context(owner, label \\ nil), do: %{job_runner: {Barrier, {owner, label}}}

  def portable_context(owner, label \\ nil) do
    name =
      Process.get({__MODULE__, :global_name}) ||
        register(owner)

    %{job_runner: {Barrier, {{:global, name}, label}}}
  end

  defp register(owner) do
    name = {__MODULE__, System.unique_integer([:positive, :monotonic])}
    :yes = :global.register_name(name, owner)
    Process.put({__MODULE__, :global_name}, name)
    name
  end
end
