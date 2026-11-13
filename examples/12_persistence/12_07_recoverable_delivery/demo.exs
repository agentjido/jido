# This example prints results for its user.
# credo:disable-for-this-file Credo.Check.Warning.IoInspect

Code.require_file("../../support/recoverable_delivery/delivery_plugin.ex", __DIR__)
Code.require_file("../../support/recoverable_delivery/sink.ex", __DIR__)
Code.require_file("../../support/recoverable_delivery/memory_sink.ex", __DIR__)
Code.require_file("../../support/recoverable_delivery/recoverable_delivery.ex", __DIR__)
Code.require_file("../../support/recoverable_delivery/delivery_worker.ex", __DIR__)

defmodule Jido.Examples.RecoverableDelivery.Probe do
  @moduledoc false
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.RecoverableDelivery, as: Agent
  alias Jido.Examples.RecoverableDelivery.MemorySink, as: Sink

  def run do
    jido = __MODULE__.Instance
    suffix = :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
    path = Path.join(System.tmp_dir!(), "jido-delivery-#{suffix}")
    persistence = {Jido.Persistence.File, path: path}

    {:ok, instance} =
      Jido.start_link(
        name: jido,
        namespace: "examples/recoverable-delivery/#{suffix}",
        persistence: persistence
      )

    {:ok, sink} = Sink.start_link(jido: jido)
    {:ok, agent_ref} = Jido.agent_ref(jido, "delivery-example")
    {:ok, ^agent_ref} = Jido.create_agent(jido, agent_ref, Agent)

    try do
      :ok = Sink.available(jido, false)
      {:ok, server} = Jido.activate_agent(jido, agent_ref)

      {:ok, route_signal_1} = Agent.record_and_deliver_signal(%{effect_id: "effect-1", value: 7})

      {:ok, _committed} =
        Jido.AgentServer.call(server, route_signal_1, [])

      committed = Server.snapshot(server)

      IO.inspect(committed.agent.state,
        label: "Committed intent while the sink is unavailable"
      )

      server_monitor = Process.monitor(server)
      Process.exit(server, :kill)
      down(server_monitor)
      :ok = Sink.available(jido, true)

      await(fn ->
        case Jido.resolve_agent(jido, agent_ref) do
          {:ok, replacement} -> replacement != server
          _other -> false
        end
      end)

      {:ok, restored} = Jido.resolve_agent(jido, agent_ref)
      await(fn -> Server.snapshot(restored).agent.state.delivery.completed == %{"effect-1" => 7} end)

      snapshot = Server.snapshot(restored)

      IO.inspect(%{state: snapshot.agent.state, revision: snapshot.agent_revision},
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
