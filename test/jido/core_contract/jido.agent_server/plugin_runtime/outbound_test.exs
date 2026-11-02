Code.require_file("../support.ex", __DIR__)

defmodule JidoTest.AgentServer.OutboundTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server.plugin_runtime", async: false
  alias Jido.AgentServer, as: Server
  alias Jido.Agent.Directive.{Emit, Reply}
  alias Jido.Signal
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

    def prepare_outbound(_runtime, signal, context, opts) do
      send(opts[:observer], {:outbound, signal, context})

      cond do
        opts[:reject] ->
          {:error, :outbound_rejected}

        context.target == :reply and opts[:corrupt_reply] == :id ->
          {:ok, %{signal | id: Signal.ID.generate!()}}

        context.target == :reply and opts[:corrupt_reply] == :causation ->
          Signal.put_context(signal, "jidocausationid", "changed-causation")

        context.target == :reply and opts[:corrupt_reply] == :trace ->
          {:ok, Signal.Trace.delete(signal)}

        true ->
          {:ok, %{signal | data: Map.put(signal.data, :prepared, true)}}
      end
    end
  end

  test "outbound preparation transforms after tracing and rejects before delivery", c do
    {:registered_name, observer} = Process.info(self(), :registered_name)

    for reject <- [false, true] do
      agent =
        Jido.Agent.define!(%{
          name: "outbound_plugin",
          schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
          plugins: [
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

  test "Reply preparation uses the reply target after correlation is present", c do
    {:registered_name, observer} = Process.info(self(), :registered_name)

    agent = outbound_agent(observer, %{})
    server = F.start(%{c | agent: agent})
    source = batch([])
    reply_signal = Signal.new!("prepared_reply", %{value: 1}, source: "/test/reply")
    {:ok, reply_signal} = Signal.put_context(reply_signal, "jidocausationid", source.id)
    source = put_in(source.data.directives, [%Reply{signal: reply_signal}])

    assert {:ok, saved, [%Reply{}]} = Server.call(server, source)
    assert_receive {:outbound, traced, context}, 1_000
    assert context.target == :reply
    assert context.source_signal.id == source.id
    assert context.agent_id == saved.id
    assert Trace.get(traced).causation_id == source.id

    assert_receive %Signal{
                     id: reply_id,
                     type: "prepared_reply",
                     data: %{value: 1, prepared: true}
                   } = delivered,
                   1_000

    assert reply_id == reply_signal.id
    assert Trace.get(delivered) == Trace.get(traced)
    assert_eventually(Server.status(server).last_effect_outcome.status == :succeeded)
  end

  test "Reply preparation cannot change correlation data", c do
    {:registered_name, observer} = Process.info(self(), :registered_name)

    for field <- [:id, :causation, :trace] do
      agent = outbound_agent(observer, %{corrupt_reply: field})
      server = F.start(%{c | agent: agent})
      source = batch([])
      reply_signal = Signal.new!("protected_reply", %{field: field}, source: "/test/reply")
      {:ok, reply_signal} = Signal.put_context(reply_signal, "jidocausationid", source.id)
      source = put_in(source.data.directives, [%Reply{signal: reply_signal}])

      assert {:ok, _, [%Reply{}]} = Server.call(server, source)
      assert_receive {:outbound, _traced, %{target: :reply}}, 1_000
      assert_eventually(match?(%{status: :failed}, Server.status(server).last_effect_outcome))
      refute_received %Signal{type: "protected_reply"}
    end
  end

  defp outbound_agent(observer, options) do
    data = Map.merge(%{observer: observer}, options)

    Jido.Agent.define!(%{
      name: "outbound_reply_plugin",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
      plugins: [
        %{
          id: Outbound.id(),
          provider: Outbound,
          vsn: Outbound.vsn(),
          data: data
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
    |> Jido.Agent.instantiate!(id: "outbound-reply-#{System.unique_integer([:positive])}")
  end
end
