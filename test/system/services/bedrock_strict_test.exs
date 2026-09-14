Code.require_file("../support/case.exs", __DIR__)
Code.require_file("../support/peers.exs", __DIR__)
Code.require_file("../support/bedrock_peers.exs", __DIR__)

defmodule JidoTest.System.Services.BedrockStrict do
  use JidoTest.System.Case, async: false
  @moduletag :service
  @moduletag skip: "Bedrock service suite paused pending upstream fixes (bedrock-kv/bedrock#319)"
  # The host control has a local File record. The scenario Agents use the
  # actual strict Bedrock adapter on isolated peers; no fallback is selected.
  @moduletag adapter: :file
  @moduletag service_profile: :bedrock_strict
  alias JidoTest.System.{BedrockPeers, ControlledAgent, Observability, Peers}

  @tag :research
  test "a strict three-node Bedrock cluster retains committed Agent state after node loss", c do
    local = start_agent(c, module: ControlledAgent)
    assert {:ok, _} = Jido.AgentServer.call(local, ControlledAgent.signal(1))
    stop_agent(c, local)
    cookie = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
    peers = for _ <- 1..3, do: Peers.start!(cookie, &on_exit/1)
    nodes = Enum.map(peers, &elem(&1, 1))
    source = Path.expand("../support/bedrock_peers.exs", __DIR__)

    for {{peer, _}, index} <- Enum.with_index(peers) do
      :peer.call(peer, Code, :require_file, [source])

      for remote <- nodes,
          remote != :peer.call(peer, Node, :self, []),
          do: assert(true == :peer.call(peer, Node, :connect, [remote]))

      assert :ok =
               rpc(peer, :prepare, [
                 Path.join(c.tmp_dir, "node-#{index}"),
                 Path.join(c.tmp_dir, "objects"),
                 nodes
               ])
    end

    boots = for {peer, _} <- peers, do: rpc(peer, :boot, [])

    for {peer, _} <- peers do
      for event <- rpc(peer, :logs, []) do
        message = event |> :logger_formatter.format(%{}) |> IO.iodata_to_binary()
        Observability.service_log(c.observer, :bedrock_strict, message)
      end
    end

    assert Enum.all?(boots, &match?({:ok, _}, &1)),
           "SYSTEM-BEDROCK-04: strict multi-node startup failed before durability could be tested: #{inspect(boots, limit: 25)}"

    [{left, _lost_node}, {right, _}, {last, _}] = peers
    {count, layout} = ready!(c, right, peers, [])
    assert map_size(layout.logs) == 3
    assert rpc(right, :log_nodes, []) |> Enum.uniq() |> length() == 3
    for {peer, _} <- peers, do: assert(:ok == rpc(peer, :start_jido, [c.namespace, c.tmp_dir]))
    assert {:ok, server} = Peers.call(left, :activate, ["strict-agent", false])
    assert {:ok, _} = Peers.call(left, :work, [server, 31])
    before = Peers.call(left, :snapshot, [server])
    assert before.state_version == 1

    assert Enum.any?(Peers.call(left, :events), fn
             {_, [:jido, :agent, :turn, :stop], _, %{committed?: true}} -> true
             _ -> false
           end)

    assert :ok = Peers.crash(left)
    {_count, recovered_layout} = ready!(c, right, peers, [count])
    assert recovered_layout.epoch > layout.epoch
    assert {:ok, restored} = Peers.call(right, :activate, ["strict-agent", :required])
    assert Peers.call(right, :snapshot, [restored]) == before
    assert {:ok, _} = Peers.call(right, :work, [restored, 32])
    assert Peers.call(right, :snapshot, [restored]).state_version == 2
    for peer <- [right, last], do: Peers.stop(peer)
    assert_empty_agent_pool(c)
    assert JidoTest.RecoverableDeliverySink.attempts(c.jido) == []

    Observability.measure(c.observer, %{
      strict_bedrock_nodes: 3,
      strict_bedrock_required_logs: 3,
      recovered_revision: 2
    })
  end

  defp rpc(peer, function, args), do: :peer.call(peer, BedrockPeers, function, args, 45_000)

  defp ready!(c, peer, peers, args) do
    try do
      rpc(peer, :ready, args)
    catch
      :exit, reason ->
        diagnostics =
          for {other, node} <- peers do
            {node, :peer.call(other, BedrockPeers, :diagnostics, [], 5_000)}
          end

        for {other, node} <- peers do
          case :peer.call(other, BedrockPeers, :logs, [], 5_000) do
            events when is_list(events) ->
              for event <- events do
                message = event |> :logger_formatter.format(%{}) |> IO.iodata_to_binary()
                Observability.service_log(c.observer, :bedrock_strict, "#{node}: #{message}")
              end

            _ ->
              :ok
          end
        end

        flunk(
          "SYSTEM-BEDROCK-04: strict cluster did not become ready: #{inspect(reason)}. Diagnostics: #{inspect(diagnostics)}. Recent logs:\n#{Observability.format_logs(c.observer)}"
        )
    end
  end
end
