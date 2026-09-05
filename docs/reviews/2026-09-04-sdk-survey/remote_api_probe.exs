# Run from the project root with: mix run /path/to/remote_api_probe.exs
# These diagnostics use real peer VMs and public Jido APIs.
defmodule JidoSurvey.RemoteApiProbe do
  alias Jido.Actor.Server
  alias Jido.Examples.RemoteCounter

  def run do
    cookie =
      :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false) |> String.to_charlist()

    {a, node_a} = start_peer(~c"survey_older", cookie)

    try do
      # Deliberately give the VMs different ages. This is a clock-domain probe.
      timer = Process.send_after(self(), :boot_younger_vm, 6_000)

      receive do
        :boot_younger_vm -> :ok
      end

      Process.cancel_timer(timer)
      {b, node_b} = start_peer(~c"survey_younger", cookie)

      try do
        true = call(a, Node, :connect, [node_b])
        true = call(b, Node, :connect, [node_a])

        {:ok, actor_a} =
          call(a, Jido, :start_actor, [JidoSurvey.Instance, RemoteCounter, [id: "older"]])

        {:ok, actor_b} =
          call(b, Jido, :start_actor, [JidoSurvey.Instance, RemoteCounter, [id: "younger"]])

        clocks = %{
          older: call(a, System, :monotonic_time, [:millisecond]),
          younger: call(b, System, :monotonic_time, [:millisecond])
        }

        local_control = call(a, RemoteCounter, :record, [actor_a, 1, [timeout: 1_000]])
        younger_to_older = capture(fn -> call(b, RemoteCounter, :record, [actor_a, 2]) end)
        local_liveness = call(a, Server, :alive?, [actor_a])
        remote_liveness = capture(fn -> call(b, Server, :alive?, [actor_a]) end)
        :ok = call(b, :sys, :suspend, [actor_b])

        expired_call =
          capture(fn -> call(a, RemoteCounter, :record, [actor_b, 3, [timeout: 100]]) end)

        :ok = call(b, :sys, :resume, [actor_b])
        after_timeout = await_snapshot(b, actor_b, 1_000)
        # Same-node control: a request that expires before admission must not commit.
        :ok = call(b, :sys, :suspend, [actor_b])

        local_expired_call =
          capture(fn -> call(b, RemoteCounter, :record, [actor_b, 4, [timeout: 100]]) end)

        :ok = call(b, :sys, :resume, [actor_b])
        local_after_timeout = call(b, Server, :snapshot, [actor_b])

        result = %{
          monotonic_clock_difference_ms: clocks.older - clocks.younger,
          local_control: simplify(local_control),
          younger_to_older_default_timeout: younger_to_older,
          local_expired_call: local_expired_call,
          local_state_after_expired_call: local_after_timeout.actor.state,
          local_revision_after_expired_call: local_after_timeout.state_version,
          local_liveness: local_liveness,
          remote_liveness: remote_liveness,
          older_to_younger_expired_call: expired_call,
          younger_state_after_expired_call: Map.take(after_timeout.actor.state, [:value]),
          younger_revision_after_expired_call: after_timeout.state_version
        }

        IO.inspect(result, pretty: true, limit: :infinity, label: "Remote API audit")
      after
        :peer.stop(b)
      end
    after
      :peer.stop(a)
    end
  end

  defp await_snapshot(peer, actor, remaining) do
    snapshot = call(peer, Server, :snapshot, [actor])

    if snapshot.state_version > 0 or remaining <= 0 do
      snapshot
    else
      receive do
      after
        10 -> await_snapshot(peer, actor, remaining - 10)
      end
    end
  end

  defp simplify({:ok, actor}), do: {:ok, actor.state}
  defp simplify(other), do: other

  defp capture(fun) do
    try do
      simplify(fun.())
    catch
      kind, reason -> {kind, inspect(reason, limit: 15)}
    end
  end

  defp call(peer, module, function, args), do: :peer.call(peer, module, function, args, 10_000)

  defp start_peer(prefix, cookie) do
    {:ok, peer, peer_node} =
      :peer.start_link(%{
        name: :peer.random_name(prefix),
        host: ~c"127.0.0.1",
        longnames: true,
        connection: :standard_io,
        args: [
          ~c"+S",
          ~c"2",
          ~c"-setcookie",
          cookie,
          ~c"-kernel",
          ~c"inet_dist_use_interface",
          ~c"{127,0,0,1}"
        ],
        wait_boot: 15_000
      })

    try do
      :ok = call(peer, :code, :add_paths, [:code.get_path()])
      {:ok, _} = call(peer, Application, :ensure_all_started, [:jido])

      {:ok, _} =
        call(peer, Supervisor, :start_child, [Jido.Supervisor, {Jido, name: JidoSurvey.Instance}])

      {peer, peer_node}
    catch
      kind, reason ->
        :peer.stop(peer)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end
end

JidoSurvey.RemoteApiProbe.run()
