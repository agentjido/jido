defmodule JidoTest.System.AuthoringLoad do
  use ExUnit.Case, async: false
  @moduletag :system
  @moduletag scenario: :burn_in
  @moduletag timeout: 120_000

  alias Jido.Agent

  @workers 4
  @payload_bytes 131_072
  @heap_slack 1_048_576
  @binary_limit 65_536
  @deadline 60_000

  defmodule Run do
    use Jido.Action,
      name: "authoring_load_run"

    @impl true
    def run(_params, context), do: {:ok, context.agent_state}
  end

  defmodule Owned do
    use Jido.Plugin

    @impl true
    def state_spec(_opts), do: {:owned, Zoi.integer() |> Zoi.default(1)}
  end

  test "repeated pure authoring and Codec operations release transient data and own no resources" do
    rounds = System.get_env("JIDO_AUTHORING_LOAD_ROUNDS", "20") |> String.to_integer()
    assert rounds in 1..1_000
    owner = self()
    token = make_ref()

    workers =
      for index <- 1..@workers do
        {pid, monitor} = spawn_monitor(fn -> worker(owner, token, index, rounds) end)
        {index, pid, monitor}
      end

    try do
      checkpoints(workers, token, :started)

      for {_index, pid, _monitor} <- workers do
        1 = :erlang.trace(pid, true, [:procs, :set_on_spawn, {:tracer, self()}])
      end

      for {_index, pid, _monitor} <- workers, do: send(pid, {:warmup, token})
      before = checkpoints(workers, token, :ready)
      for {_index, pid, _monitor} <- workers, do: send(pid, {:run, token})

      after_load = checkpoints(workers, token, :finished)
      marker = :erlang.trace_delivered(:all)
      spawned = drain_trace(marker, [])
      stop_spawned(spawned)
      assert spawned == [], "pure authoring started helper processes: #{inspect(spawned)}"

      for {index, _pid, _monitor} <- workers do
        baseline = Map.fetch!(before, index)
        retained = Map.fetch!(after_load, index)
        assert baseline.owned_ets == 0
        assert retained.owned_ets == 0
        assert retained.mailbox_messages == 0

        assert retained.process_bytes <= baseline.process_bytes + @heap_slack,
               "worker #{index} retained process memory: #{inspect({baseline, retained})}"

        assert baseline.binary_bytes <= @binary_limit,
               "worker #{index} retained warm-up binaries: #{inspect(baseline)}"

        assert retained.binary_bytes <= @binary_limit,
               "worker #{index} retained transient binaries: #{inspect({baseline, retained})}"
      end

      IO.puts(
        "Authoring load: " <>
          JSON.encode!(%{
            rounds_per_worker: rounds,
            workers: @workers,
            payload_bytes: @payload_bytes,
            post_gc_heap_slack_bytes: @heap_slack,
            post_gc_binary_limit_bytes: @binary_limit,
            before: Map.new(before, fn {index, measured} -> {to_string(index), measured} end),
            after: Map.new(after_load, fn {index, measured} -> {to_string(index), measured} end)
          })
      )

      for {_index, pid, _monitor} <- workers, do: send(pid, {:stop, token})
      for {_index, pid, monitor} <- workers, do: await_down(pid, monitor, :normal)
    after
      for {_index, pid, monitor} <- workers do
        if Process.alive?(pid) do
          :erlang.trace(pid, false, [:all])
          Process.exit(pid, :kill)
          await_down(pid, monitor)
        end

        Process.demonitor(monitor, [:flush])
      end

      marker = :erlang.trace_delivered(:all)
      stop_spawned(drain_trace(marker, []))
    end
  end

  defp worker(owner, token, index, rounds) do
    send(owner, {token, :started, index, self(), :ok})

    receive do
      {:warmup, ^token} -> :ok
    after
      @deadline -> raise "authoring load warm-up barrier missing"
    end

    cycle(index, 0)
    send(owner, {token, :ready, index, self(), snapshot()})

    receive do
      {:run, ^token} -> run_rounds(index, rounds)
    after
      @deadline -> raise "authoring load start barrier missing"
    end

    send(owner, {token, :finished, index, self(), snapshot()})

    receive do
      {:stop, ^token} -> :ok
    after
      @deadline -> raise "authoring load stop barrier missing"
    end
  end

  defp run_rounds(_index, 0), do: :ok

  defp run_rounds(index, remaining) do
    cycle(index, remaining)
    run_rounds(index, remaining - 1)
  end

  defp cycle(index, round) do
    payload = :binary.copy(<<65 + rem(round, 26)>>, @payload_bytes)

    definition =
      Agent.define!(%{
        name: "load_member",
        schema:
          Zoi.object(%{
            count: Zoi.integer() |> Zoi.default(0),
            payload: Zoi.string() |> Zoi.default("")
          }),
        extensions: [%{id: Owned.id(), provider: Owned, vsn: Owned.vsn(), data: %{}}],
        metadata: %{payload: payload},
        routes: [
          %{
            path: "load.run",
            handler: %{kind: :action, target: Run},
            state: %{source: :output, path: []}
          }
        ]
      })

    registry = JidoTest.AgentRegistry.for(definition)
    {:ok, document} = JidoTest.AgentRegistry.encode(definition, registry)
    {:ok, ^definition} = JidoTest.AgentRegistry.decode(json_copy(document), registry)
    state = %{count: round, payload: payload}
    id = "load-#{index}-#{round}"
    {:ok, agent} = Agent.instantiate(definition, id: id, state: state)
    assert agent.state === Map.put(state, :owned, 1)
    assert Agent.definition(agent) === definition
    assert {:error, _} = Agent.instantiate(definition, id: id, state: %{count: :bad})

    :ok
  end

  defp json_copy(document), do: document |> JSON.encode!() |> JSON.decode!()

  defp snapshot do
    :erlang.garbage_collect(self(), [{:type, :major}])
    info = Process.info(self(), [:memory, :binary, :message_queue_len])

    %{
      process_bytes: info[:memory],
      binary_bytes:
        info[:binary]
        |> Map.new(fn {id, bytes, _refs} -> {id, bytes} end)
        |> Map.values()
        |> Enum.sum(),
      mailbox_messages: info[:message_queue_len],
      owned_ets: Enum.count(:ets.all(), &(:ets.info(&1, :owner) == self()))
    }
  end

  defp checkpoints(workers, token, phase) do
    Map.new(workers, fn {index, pid, monitor} ->
      receive do
        {^token, ^phase, ^index, ^pid, measured} ->
          {index, measured}

        {:DOWN, ^monitor, :process, ^pid, reason} ->
          flunk("authoring worker failed: #{inspect(reason)}")
      after
        @deadline -> flunk("authoring worker did not reach #{phase}")
      end
    end)
  end

  defp drain_trace(marker, spawned) do
    receive do
      {:trace_delivered, :all, ^marker} -> Enum.reverse(spawned)
      {:trace, _parent, :spawn, pid, mfa} -> drain_trace(marker, [{pid, mfa} | spawned])
      {:trace, _pid, _event, _detail} -> drain_trace(marker, spawned)
    after
      @deadline -> flunk("authoring trace delivery barrier missing")
    end
  end

  defp await_down(pid, monitor, reason) do
    receive do
      {:DOWN, ^monitor, :process, ^pid, ^reason} -> :ok
    after
      @deadline -> flunk("authoring worker did not stop: #{inspect(pid)}")
    end
  end

  defp await_down(pid, monitor) do
    receive do
      {:DOWN, ^monitor, :process, ^pid, _reason} -> :ok
    after
      @deadline -> flunk("authoring worker did not stop: #{inspect(pid)}")
    end
  end

  defp stop_spawned([]), do: :ok

  defp stop_spawned(spawned) do
    for {pid, _mfa} <- spawned do
      monitor = Process.monitor(pid)
      Process.exit(pid, :kill)
      await_down(pid, monitor)
    end

    marker = :erlang.trace_delivered(:all)
    stop_spawned(drain_trace(marker, []))
  end
end
