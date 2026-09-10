# This example prints results for its user.
# credo:disable-for-this-file Credo.Check.Warning.IoInspect

defmodule Jido.Examples.RecoverableDelivery.Probe do
  @moduledoc false
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.RecoverableDelivery, as: Agent
  alias Jido.Examples.RecoverableDelivery.MemorySink, as: Sink

  def run do
    jido = __MODULE__.Instance
    suffix = :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
    path = Path.join(System.tmp_dir!(), "jido-delivery-#{suffix}")
    {:ok, instance} = Jido.start_link(name: jido)
    {:ok, sink} = Sink.start_link(jido: jido)
    persistence = {Jido.Persistence.File, path: path}
    opts = [id: "delivery-example", persistence: persistence, restart: :temporary]

    try do
      :ok = Sink.available(jido, false)
      {:ok, server} = Jido.start_agent(jido, Agent, opts ++ [restore: false])
      {:ok, committed} = Agent.record_and_deliver(server, "effect-1", 7)
      IO.inspect(committed.state, label: "Committed intent while the sink is unavailable")
      agent_ref = Process.monitor(server)
      Process.exit(server, :kill)
      down(agent_ref)
      :ok = Sink.available(jido, true)
      {:ok, restored} = Jido.start_agent(jido, Agent, opts ++ [restore: :required])
      await(fn -> Server.agent(restored).state.delivery.completed == %{"effect-1" => 7} end)

      snapshot = Server.snapshot(restored)

      IO.inspect(%{state: snapshot.agent.state, revision: snapshot.state_version},
        label: "Restored; worker retried and committed confirmation"
      )

      IO.inspect(Sink.records(jido), label: "One external record")
    after
      GenServer.stop(sink)
      Supervisor.stop(instance)
      File.rm_rf!(path)
    end
  end

  defp down(ref) do
    receive do
      {:DOWN, ^ref, :process, _pid, _reason} -> :ok
    after
      2_000 -> raise "Process did not stop"
    end
  end

  defp await(check), do: await(check, System.monotonic_time(:millisecond) + 2_000)

  defp await(check, deadline) do
    cond do
      check.() ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        raise "Recovery did not complete"

      true ->
        receive do
        after
          10 -> await(check, deadline)
        end
    end
  end
end

Jido.Examples.RecoverableDelivery.Probe.run()
