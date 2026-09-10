defmodule JidoTest.JobRunner.Barrier do
  @moduledoc false

  @behaviour Jido.Examples.Runtime.JobRunner

  @impl true
  def run({owner, label}, value) do
    send(owner, {:job_work, self(), label || value})

    receive do
      :release -> {:ok, Integer.to_string(value * 2)}
      {:finish, result} -> result
    after
      5_000 -> raise "job runner barrier was not released"
    end
  end
end

defmodule JidoTest.JobRunner do
  @moduledoc false

  alias JidoTest.JobRunner.Barrier

  def context(owner, label \\ nil), do: %{job_runner: {Barrier, {owner, label}}}
end
