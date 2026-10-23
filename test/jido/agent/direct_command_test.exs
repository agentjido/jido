defmodule Jido.Agent.DirectCommandTest do
  use ExUnit.Case, async: true
  alias Jido.Agent
  alias Jido.Agent.Directive
  alias Jido.Signal

  defmodule Update do
    use Jido.Action,
      name: "direct_agent_update"

    def run(input, context) do
      if pid = Map.get(context, :probe), do: send(pid, {:ran, self(), context.signal, input})

      case Map.get(input, :mode) do
        :fail ->
          {:error, :rejected}

        :partial ->
          {:ok, %{count: 9}}

        :invalid ->
          {:ok, %{context.agent_state | count: "wrong"}}

        :owned ->
          {:ok, Map.put(context.agent_state, :owned, 99)}

        :continue ->
          {:continue, %{amount: 4}, Jido.Agent.DirectCommandTest.Update}

        _ ->
          {:ok,
           %{context.agent_state | count: context.agent_state.count + Map.get(input, :amount, 1)},
           Map.get(input, :directives, [])}
      end
    end
  end

  defmodule Leaf do
    use Jido.Agent, name: "direct"

    state do
      schema Zoi.object(%{
               count: Zoi.integer() |> Zoi.default(0),
               label: Zoi.string() |> Zoi.default("same")
             })
    end

    routes do
      signal_source "/direct"

      route "work", Jido.Agent.DirectCommandTest.Update
    end
  end

  defmodule Finish do
    use Jido.Action,
      name: "direct_agent_finish"

    def run(state, _context), do: {:ok, %{state | count: state.count + 2}}
  end

  defmodule Flow do
    use Jido.Flow,
      name: "direct_agent_flow",
      schema: Zoi.object(%{amount: Zoi.integer()})

    flow do
      step "update",
        action: Jido.Agent.DirectCommandTest.Update,
        params: %{amount: input(:amount)}

      step "finish", action: Jido.Agent.DirectCommandTest.Finish, params: result("update")
      output result("finish")
    end
  end

  defmodule Worker do
    use Jido.Agent, name: "direct_worker"

    routes do
      route "work", Jido.Agent.DirectCommandTest.Update
    end
  end

  defmodule Owned do
    use Jido.Plugin, id: "test.direct.owned"
    def state_spec(_), do: {:owned, Zoi.integer() |> Zoi.default(0)}

    def reduce(reduction, _opts) do
      send(self(), :reduced)
      {:ok, reduction.plugin_state + 1}
    end
  end

  defmodule Label do
    use Jido.Agent.Extension, id: "test.direct.label"
  end

  defmodule UnknownDirective do
    use Jido.Agent.Directive
    defstruct []
  end

  defp route(path, handler, opts \\ []) do
    Map.merge(
      %{path: path, handler: handler, state: %{source: :output, path: []}},
      Map.new(opts)
    )
  end

  defp action(path \\ "work", opts \\ []),
    do: route(path, %{kind: :action, target: Update}, opts)

  defp instance(routes \\ [action()], extensions \\ []) do
    Agent.define!(%{
      name: "direct",
      signal_source: "/direct",
      schema:
        Zoi.object(%{
          count: Zoi.integer() |> Zoi.default(0),
          label: Zoi.string() |> Zoi.default("same")
        }),
      routes: routes,
      extensions: extensions
    })
    |> Agent.instantiate!(id: "direct-1")
  end

  defp signal(type \\ "work", data \\ %{}), do: Signal.new!(type, data, source: "/test")

  defp owned, do: %{id: Owned.id(), provider: Owned, vsn: Owned.vsn(), data: %{}}

  test "DSL and independent Map and struct definitions produce the exact same command result" do
    fields = %{
      name: "direct",
      module: Leaf,
      signal_source: "/direct",
      schema:
        Zoi.object(%{
          count: Zoi.integer() |> Zoi.default(0),
          label: Zoi.string() |> Zoi.default("same")
        }),
      routes: [action("work")],
      topology: %{agents: [], connections: []}
    }

    raw_struct = struct!(Agent, fields)
    from_map = Agent.define!(fields)
    assert Agent.define!(raw_struct) === Leaf.definition()
    assert from_map === Leaf.definition()
    input = signal("work", %{amount: 2})
    expected = %{from_map | id: "direct-1", state: %{count: 2, label: "same"}}

    for source <- [from_map, Agent.define!(raw_struct), Leaf] do
      before = Agent.instantiate!(source, id: "direct-1")
      assert {:ok, ^expected, []} = Agent.cmd(before, input)
    end
  end

  test "a direct command runs synchronously and preserves all definition fields" do
    before = instance([action("work", defaults: %{amount: 3})])
    input = signal("work", %{amount: 2})
    assert {:ok, after_agent, []} = Agent.cmd(before, input, context: %{probe: self()})
    assert_receive {:ran, pid, ^input, %{amount: 2}}
    assert is_pid(pid)
    assert after_agent == %{before | state: %{count: 2, label: "same"}}
    assert before.state.count == 0
    assert Agent.definition(after_agent) === Agent.definition(before)
    assert {:ok, next, []} = Agent.cmd(after_agent, signal())
    assert next.state.count == 5
  end

  test "a multi-step Flow finishes the full turn and propagates unsupported executable results" do
    before = instance([route("work", %{kind: :flow, target: Flow})])
    assert {:ok, after_agent, []} = Agent.cmd(before, signal("work", %{amount: 5}))
    assert after_agent.state.count == 7

    assert {:error, %{details: %{reason: :unsupported_continuation}}} =
             Agent.cmd(instance(), signal("work", %{mode: :continue}))
  end

  test "the first declared match wins, including an explicit wildcard" do
    before =
      instance([
        action("work.*", defaults: %{amount: 3}),
        action("work.now", defaults: %{amount: 99})
      ])

    assert {:ok, result, []} = Agent.cmd(before, signal("work.now"), context: %{probe: self()})
    assert result.state.count == 3
    assert_receive {:ran, _, _, %{amount: 3}}
    assert {:error, _} = Agent.cmd(before, signal("unmatched"))
  end

  test "a matched handler failure never selects a later wildcard" do
    before = instance([action("work.now"), action("work.*")])

    assert {:error, %{details: %{reason: :rejected}}} =
             Agent.cmd(before, signal("work.now", %{mode: :fail}), context: %{probe: self()})

    assert_receive {:ran, _, _, %{mode: :fail}}
    assert before.state.count == 0
  end

  test "invalid or partial state and malformed directive batches reject the candidate" do
    before = instance()

    for input <- [
          %{mode: :invalid},
          %{mode: :partial},
          %{directives: :bad},
          %{directives: [Jido.AgentServer.Directive.server_stop() | :bad]},
          %{directives: [%UnknownDirective{}]},
          %{directives: [%{unknown: true}]},
          %{directives: [%Directive.Emit{signal: :bad}]},
          %{directives: [%{kind: :emit, type: "work.done", data: %{}, unknown: true}]}
        ] do
      assert {:error, _} = Agent.cmd(before, signal("work", input))
      assert before.state === %{count: 0, label: "same"}
    end
  end

  test "definition changes are validated as one complete local candidate" do
    member = %{name: :worker, definition: Worker, count: 1, initial_state: %{}}
    change = Directive.agent_add(:worker, Worker)
    before = instance()

    assert {:ok, after_agent, [^change]} =
             Agent.cmd(before, signal("work", %{directives: [change]}))

    assert after_agent.topology.agents == [member]
    assert before.topology.agents == []
    assert {:error, _} = Agent.cmd(before, signal("work", %{directives: [change, change]}))
  end

  test "Plugin directives add, configure and remove owned state without starting services" do
    before = instance()
    add = Directive.plugin_add(Owned)
    assert {:ok, added, [^add]} = Agent.cmd(before, signal("work", %{directives: [add]}))
    assert added.state.owned == 0
    assert length(added.extensions) == 1

    assert {:ok, removed, [_]} =
             Agent.cmd(
               added,
               signal("work", %{directives: [Directive.plugin_remove(Owned, state: :discard)]})
             )

    refute Map.has_key?(removed.state, :owned)
    assert removed.extensions == []
    assert before.extensions == []
  end

  test "Plugin edits preserve extension data and declaration order" do
    label = %{id: Label.id(), provider: Label, vsn: Label.vsn(), data: %{label: "keep"}}
    before = instance([action()], [owned(), label])
    configure = Directive.plugin_configure(Owned, [])
    assert {:ok, after_agent, [_]} = Agent.cmd(before, signal("work", %{directives: [configure]}))
    assert after_agent.extensions === before.extensions

    assert {:ok, removed, [_]} =
             Agent.cmd(
               after_agent,
               signal("work", %{directives: [Directive.plugin_remove(Owned, state: :discard)]})
             )

    assert removed.extensions === [label]
  end

  test "Scheduler owns its Directives and changes schedule state, not definition data" do
    scheduler = Jido.Plugin.Scheduler
    contribution = %{id: scheduler.id(), provider: scheduler, vsn: scheduler.vsn(), data: %{}}
    before = instance([action()], [contribution])
    tick = signal("tick")
    add = scheduler.cron("refresh", "*/5 * * * *", tick, timezone: "Etc/UTC")

    assert {:error, _} =
             Agent.cmd(instance(), signal("work", %{amount: 0, directives: [add]}))

    assert {:ok, added, [_]} =
             Agent.cmd(before, signal("work", %{amount: 0, directives: [add]}))

    assert added.state.scheduler.cron["refresh"].cron_expression == "*/5 * * * *"
    assert added.state.scheduler.cron["refresh"].message === tick
    assert Agent.definition(added) === Agent.definition(before)
    assert before.state.scheduler.cron === %{}

    replace = scheduler.cron("refresh", "0 * * * *", tick, timezone: "Etc/UTC")

    assert {:ok, replaced, [_]} =
             Agent.cmd(added, signal("work", %{amount: 0, directives: [replace]}))

    assert replaced.state.scheduler.cron["refresh"].cron_expression == "0 * * * *"
    assert map_size(replaced.state.scheduler.cron) == 1

    cancel = scheduler.cancel("refresh")

    assert {:ok, removed, [^cancel]} =
             Agent.cmd(replaced, signal("work", %{amount: 0, directives: [cancel]}))

    assert removed.state === before.state
    assert removed.extensions === before.extensions
  end

  test "a Scheduler one-shot is returned as runtime work and does not edit schedule state" do
    scheduler = Jido.Plugin.Scheduler
    contribution = %{id: scheduler.id(), provider: scheduler, vsn: scheduler.vsn(), data: %{}}
    before = instance([action()], [contribution])
    delayed = scheduler.schedule(1_000, signal("tick"))

    assert {:ok, after_agent, [^delayed]} =
             Agent.cmd(before, signal("work", %{amount: 0, directives: [delayed]}))

    assert after_agent === before
  end

  test "outbound directives are returned without dispatch" do
    output = signal("work.done")
    directive = Jido.AgentServer.Directive.signal_send(output, self())

    assert {:ok, _, [^directive]} =
             Agent.cmd(instance(), signal("work", %{directives: [directive]}))

    refute_received {:signal, ^output}
    refute_received ^output
  end

  test "one Reply is correlated to the current request" do
    before = instance([action("work")])
    request = signal("work")
    output = signal("work.reply")
    {:ok, correlated} = Signal.put_context(output, "jidocausationid", request.id)
    reply = Directive.reply(correlated)

    assert {:ok, after_agent, [^reply]} =
             Agent.cmd(before, %{request | data: %{directives: [reply]}})

    assert after_agent.state.count == 1

    {:ok, wrong} = Signal.put_context(output, "jidocausationid", "other-request")

    for directives <- [[Directive.reply(wrong)], [reply, reply]] do
      assert {:error, %Jido.Error.ValidationError{}} =
               Agent.cmd(before, %{request | data: %{directives: directives}})
    end
  end

  test "repeated direct commands have no deduplication or durable state" do
    before = instance()
    input = signal()
    assert {:ok, once, []} = Agent.cmd(before, input)
    assert {:ok, twice, []} = Agent.cmd(once, input)
    assert twice.state.count == 2
    assert {:ok, ^once, []} = Agent.cmd(before, input)
  end

  test "definitions, invalid input and reserved context cannot run a command" do
    before = instance()
    assert {:error, _} = Agent.cmd(Agent.definition(before), signal())
    assert {:error, _} = Agent.cmd(before, signal(), context: %{agent_state: %{count: 999}})
    assert {:error, _} = Agent.cmd(before, signal(), [:not_keyword])
  end
end

defmodule Jido.Agent.ReplyDirectiveRuntimeTest do
  use JidoTest.Case, async: true

  alias Jido.Agent.DirectCommandTest.Leaf
  alias Jido.Agent.Directive
  alias Jido.AgentServer
  alias Jido.Signal

  test "live runtime delivers Reply to the current requester after commit", %{
    jido: jido
  } do
    {:ok, server} = JidoTest.AgentServerAssertions.start_agent(jido, Leaf)
    request = Signal.new!("work", %{}, source: "/test")
    output = Signal.new!("work.reply", %{}, source: "/direct")
    {:ok, output} = Signal.put_context(output, "jidocausationid", request.id)
    reply = Directive.reply(output)
    request = %{request | data: %{directives: [reply]}}

    assert {:ok, committed, [^reply]} = AgentServer.call(server, request)
    assert_receive %Signal{id: output_id, type: "work.reply", data: %{}} = delivered
    assert output_id == output.id
    assert Signal.get_context(delivered, "jidocausationid") == request.id
    assert Signal.Trace.get(delivered) != nil
    assert AgentServer.status(server).state_version == 1
    assert AgentServer.agent(server) == committed
  end
end
