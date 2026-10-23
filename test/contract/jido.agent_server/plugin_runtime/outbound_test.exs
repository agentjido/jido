Code.require_file("../support.ex", __DIR__)

defmodule JidoTest.AgentServer.OutboundTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server.plugin_runtime", async: false
  alias Jido.AgentServer, as: Server
  alias Jido.Agent.Directive.Emit
  alias Jido.Tracing.Trace
  alias JidoTest.AgentServer.Fixtures, as: F
  import JidoTest.Eventually
  @moduletag obligation: "jido.agent_server.plugin_runtime.I8"

  setup do
    Process.register(
      self(),
      Module.concat(__MODULE__, "Observer#{System.unique_integer([:positive])}")
    )

    F.setup_runtime()
  end

  defp batch(directives), do: F.signal(%{mode: :batch, directives: directives})

  defmodule Outbound do
    use Jido.Plugin

    def prepare_dispatch(_runtime, signal, context, opts) do
      send(opts[:observer], {:outbound, signal, context})

      if opts[:reject],
        do: {:error, :outbound_rejected},
        else: {:ok, %{signal | data: Map.put(signal.data, :prepared, true)}}
    end
  end

  test "outbound preparation transforms after tracing and rejects before delivery", c do
    {:registered_name, observer} = Process.info(self(), :registered_name)

    for reject <- [false, true] do
      agent =
        Jido.Agent.define!(%{
          name: "outbound_plugin",
          schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
          extensions: [
            %{
              id: Outbound.id(),
              provider: Outbound,
              vsn: Outbound.vsn(),
              data: %{observer: observer, reject: reject}
            }
          ],
          routes: [
            %{
              path: "work",
              handler: %{kind: :action, target: F.Work},
              state: %{source: :output, path: []}
            }
          ]
        })
        |> Jido.Agent.instantiate!(id: "outbound-#{reject}")

      server = F.start(%{c | agent: agent})
      assert :ok = Server.await_ready(server)
      output = F.signal(%{}, "prepared_output")
      source = batch([%Emit{signal: output, dispatch: {:pid, target: self()}}])
      assert {:ok, saved, [_]} = Server.call(server, source)
      assert_receive {:outbound, traced, context}, 1_000
      assert Trace.get(traced).causation_id == source.id
      assert context.source_signal.id == source.id
      assert context.agent_id == saved.id
      assert context.state_version == 1
      assert_eventually(Server.status(server).phase == :idle)

      if reject do
        refute_received {:signal, %{type: "prepared_output"}}
        assert Server.status(server).last_effect_outcome.status == :failed
      else
        assert_receive {:signal, %{type: "prepared_output", data: %{prepared: true}}}, 1_000
        assert Server.status(server).last_effect_outcome.status == :succeeded
      end
    end
  end
end
