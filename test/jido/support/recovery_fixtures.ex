defmodule JidoTest.RecoveryFixtures do
  @moduledoc false
  alias Jido.Examples.PendingJobRecovery, as: Agent

  def approve_held(server, observer) do
    work = fn value ->
      task = self()
      Elixir.Agent.update(observer, fn _ -> task end)

      receive do
        :release -> {:ok, Integer.to_string(value * 2)}
      end
    end

    Agent.approve_job(server, "job-1", "attempt-1", context: %{work: work})
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
