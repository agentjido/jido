defmodule JidoTest.RecoveryFixtures do
  @moduledoc false
  alias Jido.Examples.PendingJobRecovery, as: Agent

  def approve_held(server, observer) do
    Agent.approve_job(server, "job-1", "attempt-1",
      context: %{job_runner: {__MODULE__.Runner, observer}}
    )
  end
end

defmodule JidoTest.RecoveryFixtures.Runner do
  @moduledoc false

  @behaviour Jido.Examples.Runtime.JobRunner

  @impl true
  def run(observer, value) do
    Elixir.Agent.update(observer, fn _ -> self() end)

    receive do
      :release -> {:ok, Integer.to_string(value * 2)}
    after
      5_000 -> raise "recovery runner was not released"
    end
  end
end

defmodule JidoTest.RecoveryStore do
  @moduledoc false
  @behaviour Jido.Persistence.Adapter
  @impl true
  def get(key, _opts), do: Jido.Persistence.File.get(key, options())
  @impl true
  def put(key, value, _opts), do: Jido.Persistence.File.put(key, value, options())
  @impl true
  def delete(key, _opts), do: Jido.Persistence.File.delete(key, options())
  @impl true
  def compare_and_swap(key, expected, value, _opts),
    do: Jido.Persistence.File.compare_and_swap(key, expected, value, options())

  defp options, do: Application.fetch_env!(:jido, __MODULE__)
end

defmodule JidoTest.RecoveryInstance do
  @moduledoc false
  use Jido, otp_app: :jido, persistence: JidoTest.RecoveryStore

  def start_for_test(path) do
    Application.put_env(:jido, JidoTest.RecoveryStore, path: path)
    Supervisor.start_child(Jido.Supervisor, {__MODULE__, []})
  end
end
