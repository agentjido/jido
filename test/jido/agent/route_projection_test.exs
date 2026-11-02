defmodule Jido.Agent.RouteProjectionTest do
  use JidoTest.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Directive
  alias Jido.Agent.Directive.Reply
  alias Jido.AgentServer
  alias Jido.Signal

  defmodule SelectedState do
    defstruct [:count]
  end

  defmodule Project do
    use Jido.Action,
      name: "route_projection_project",
      output_schema:
        Zoi.object(%{
          state: Zoi.any() |> Zoi.optional(),
          reply: Zoi.any() |> Zoi.optional()
        })

    @impl Jido.Action
    def run(params, context) do
      output =
        case Map.get(params, :mode) do
          :missing_state ->
            %{reply: Map.get(params, :reply)}

          :missing ->
            %{state: context.agent_state}

          :partial ->
            %{state: %{}, reply: Map.get(params, :reply)}

          :struct ->
            %{state: %SelectedState{count: 1}, reply: Map.get(params, :reply)}

          _other ->
            %{
              state: %{count: context.agent_state.count + 1},
              reply: Map.get(params, :reply)
            }
        end

      {:ok, output, Map.get(params, :directives, [])}
    end
  end

  defmodule Envelope do
    use Jido.Action, name: "route_projection_envelope"

    @impl Jido.Action
    def run(_params, _context), do: {:ok, Jido.Action.Output.raw(%{count: 1})}
  end

  defmodule RootReply do
    use Jido.Action,
      name: "route_projection_root_reply",
      output_schema: Zoi.object(%{value: Zoi.integer()})

    @impl Jido.Action
    def run(_params, _context), do: {:ok, %{value: 1}}
  end

  defmodule Barrier do
    use Jido.Action,
      name: "route_projection_barrier"

    @impl Jido.Action
    def run(_params, context), do: {:ok, context.agent_state}
  end

  defmodule BlockingProject do
    use Jido.Action,
      name: "route_projection_blocking_project",
      output_schema:
        Zoi.object(%{
          state: Zoi.map(),
          reply: Zoi.any()
        })

    @impl Jido.Action
    def run(%{test_pid: test_pid}, context) do
      send(test_pid, {:route_projection_started, self()})

      receive do
        :finish ->
          {:ok, %{state: %{count: context.agent_state.count + 1}, reply: %{value: 1}}}
      end
    end
  end

  defmodule ReplyReducer do
    use Jido.Plugin, id: "test.route_projection.reply_reducer"

    @impl Jido.Plugin
    def state_spec(_opts), do: {:reply_reductions, Zoi.integer() |> Zoi.default(0)}

    @impl Jido.Plugin
    def reduce(reduction, _opts) do
      if Enum.any?(reduction.directives, &match?(%Reply{}, &1)),
        do: {:ok, reduction.plugin_state + 1},
        else: {:error, :generated_reply_missing}
    end
  end

  defp selector(path), do: %{source: :output, path: List.wrap(path)}

  defp project_route(state \\ selector(:state), reply \\ selector(:reply)) do
    %{
      path: "project",
      handler: %{kind: :action, target: Project},
      state: state,
      reply: %{type: "project.done", from: reply}
    }
  end

  defp barrier_route do
    %{
      path: "barrier",
      handler: %{kind: :action, target: Barrier},
      state: :unchanged
    }
  end

  defp agent(routes, extensions \\ []) do
    Agent.define!(%{
      name: "route_projection",
      signal_source: "/agent/route-projection",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
      routes: routes,
      plugins: extensions
    })
    |> Agent.instantiate!(id: Jido.Signal.ID.generate!())
  end

  defp request(data \\ %{}) do
    signal = Signal.new!("project", data, source: "/test")
    {:ok, signal, trace} = Signal.Trace.ensure(signal)
    {signal, trace}
  end

  defp plugin_extension do
    %{
      id: ReplyReducer.id(),
      provider: ReplyReducer,
      vsn: ReplyReducer.vsn(),
      data: %{}
    }
  end

  def transform(signal), do: {:ok, %{signal | type: "project.transformed"}}

  test "projects complete state and appends one correlated reply" do
    before = agent([project_route()])
    reply_data = %{value: 7}
    {source, trace} = request(%{reply: reply_data})

    assert {:ok, after_agent, [%Reply{signal: reply}]} = Agent.cmd(before, source)
    assert after_agent.state == %{count: 1}
    assert reply.type == "project.done"
    assert reply.source == "/agent/route-projection"
    assert reply.data === reply_data
    assert reply.id != source.id
    assert Signal.Trace.get(reply) == trace
    assert Signal.get_context(reply, "jidocausationid") == source.id
  end

  test "unchanged state is selected before Plugin reduction" do
    before = agent([project_route(:unchanged)], [plugin_extension()])
    {source, _trace} = request(%{reply: %{value: 1}})

    assert {:ok, after_agent, [%Reply{}]} = Agent.cmd(before, source)
    assert after_agent.state.count == before.state.count
    assert after_agent.state.reply_reductions == 1
  end

  test "missing reply output fails but a present nil value stays selected" do
    before = agent([project_route(:unchanged)])
    {missing, _trace} = request(%{mode: :missing})

    assert {:error,
            %Agent.Error{
              code: :missing_output_field,
              path: [:reply, :from, :path, 0]
            }} = Agent.cmd(before, missing)

    assert before.state == %{count: 0}

    {present, _trace} = request(%{reply: nil})

    assert {:ok, unchanged, [%Reply{signal: %{data: nil}}]} = Agent.cmd(before, present)
    assert unchanged === before
  end

  test "missing selected state fails direct and live execution before reply", %{jido: jido} do
    before = agent([project_route()])
    {source, _trace} = request(%{mode: :missing_state, reply: %{value: 1}})

    expected_error = %Agent.Error{
      code: :missing_output_field,
      path: [:state, :path, 0],
      message: "Selected output field is missing",
      details: %{key: :state}
    }

    assert {:error, ^expected_error} = Agent.cmd(before, source)
    assert before.state == %{count: 0}

    assert {:ok, server} = JidoTest.AgentServerAssertions.start_agent(jido, before)
    assert {:error, ^expected_error} = AgentServer.call(server, source)
    assert AgentServer.agent(server) === before
    assert AgentServer.status(server).state_version == 0
    refute_received %Signal{type: "project.done"}
  end

  test "a root selector returns the validated output unchanged" do
    route = %{
      path: "project",
      handler: %{kind: :action, target: RootReply},
      state: :unchanged,
      reply: %{type: "project.done", from: selector([])}
    }

    before = agent([route])
    {source, _trace} = request()

    assert {:ok, unchanged, [%Reply{signal: %{data: %{value: 1}}}]} =
             Agent.cmd(before, source)

    assert unchanged === before
  end

  test "a transform route keeps the prepared state" do
    route = %{
      path: "project",
      handler: %{kind: :transform, target: {__MODULE__, :transform, 1}}
    }

    before = agent([route])
    {source, _trace} = request()

    assert {:ok, unchanged, [%Directive.Emit{signal: transformed}]} = Agent.cmd(before, source)
    assert unchanged === before
    assert transformed.type == "project.transformed"
  end

  test "selected state must be one complete plain Agent state" do
    before = agent([project_route()])

    for mode <- [:partial, :struct] do
      {source, _trace} = request(%{mode: mode, reply: %{value: 1}})
      assert {:error, %Agent.Error{}} = Agent.cmd(before, source)
    end

    assert before.state == %{count: 0}
  end

  test "a manual Reply and a generated Reply fail the complete batch" do
    before = agent([project_route()])
    {source, trace} = request(%{reply: %{value: 1}})

    manual_signal = Signal.new!("manual.done", %{}, source: "/manual")
    {:ok, manual_signal} = Signal.Trace.put(manual_signal, trace)
    {:ok, manual_signal} = Signal.put_context(manual_signal, "jidocausationid", source.id)
    manual = Directive.reply(manual_signal)
    source = %{source | data: Map.put(source.data, :directives, [manual])}

    assert {:error,
            %Jido.Error.ValidationError{
              message: "Agent turn can return only one Reply Directive"
            }} = Agent.cmd(before, source)

    assert before.state == %{count: 0}
  end

  test "the selected route projects before its mutation changes later turns" do
    before = agent([project_route()])
    remove = Directive.route_remove("project")
    {source, _trace} = request(%{reply: %{value: 1}, directives: [remove]})

    assert {:ok, after_agent, [^remove, %Reply{}]} = Agent.cmd(before, source)
    assert after_agent.state == %{count: 1}
    assert after_agent.routes == []
    assert {:error, %Agent.Error{code: :unmatched_input}} = Agent.cmd(after_agent, source)
  end

  test "direct and live execution use the same projection path", %{jido: jido} do
    before = agent([project_route()])
    {source, _trace} = request(%{reply: %{value: 1}})

    assert {:ok, direct, [%Reply{signal: direct_reply}]} = Agent.cmd(before, source)
    assert {:ok, server} = JidoTest.AgentServerAssertions.start_agent(jido, before)
    assert {:ok, live, [%Reply{signal: live_reply}]} = AgentServer.call(server, source)
    assert_receive %Signal{} = delivered_reply

    assert live === direct

    assert Map.drop(Map.from_struct(delivered_reply), [:extensions]) ==
             Map.drop(Map.from_struct(live_reply), [:extensions])

    assert Signal.get_context(delivered_reply, "jidocausationid") == source.id

    assert Map.drop(Map.from_struct(live_reply), [:id]) ==
             Map.drop(Map.from_struct(direct_reply), [:id])
  end

  test "a generated Reply runs before a terminal ServerStop", %{jido: jido} do
    before = agent([project_route()])
    stop = Jido.AgentServer.Directive.server_stop()
    {source, _trace} = request(%{reply: %{value: 1}, directives: [stop]})
    {:ok, server} = JidoTest.AgentServerAssertions.start_agent(jido, before)
    monitor = Process.monitor(server)

    assert {:ok, committed, [%Reply{signal: reply}, ^stop]} = AgentServer.call(server, source)
    assert committed.state == %{count: 1}
    assert reply.data == %{value: 1}
    assert_receive %Signal{id: reply_id, type: "project.done", data: %{value: 1}}
    assert reply_id == reply.id
    assert_receive {:DOWN, ^monitor, :process, ^server, :normal}
  end

  test "a cast with a generated reply fails before commit", %{jido: jido} do
    before = agent([project_route(), barrier_route()])
    {source, _trace} = request(%{reply: %{value: 1}})
    {:ok, server} = JidoTest.AgentServerAssertions.start_agent(jido, before)

    assert :ok = AgentServer.cast(server, source)
    barrier = Signal.new!("barrier", %{}, source: "/test")
    assert {:ok, barrier_result, []} = AgentServer.call(server, barrier)

    assert barrier_result.state == before.state
    assert AgentServer.status(server).state_version == 1
  end

  test "cancellation stops output before route projection", %{jido: jido} do
    route = %{
      project_route()
      | handler: %{kind: :action, target: BlockingProject}
    }

    before = agent([route])
    {source, _trace} = request(%{test_pid: self()})
    {:ok, server} = JidoTest.AgentServerAssertions.start_agent(jido, before)
    caller = Task.async(fn -> AgentServer.call(server, source) end)

    assert_receive {:route_projection_started, worker}
    assert :ok = AgentServer.cancel(server)
    assert {:error, :cancelled} = Task.await(caller)
    refute Process.alive?(worker)
    assert AgentServer.agent(server) === before
    assert AgentServer.status(server).state_version == 0
  end

  test "an Action Output envelope remains invalid route output" do
    before =
      agent([
        %{
          path: "project",
          handler: %{kind: :action, target: Envelope},
          state: selector([])
        }
      ])

    {source, _trace} = request()

    assert {:error,
            %Jido.Error.ExecutionError{
              message: "Agent executable output must be a plain state map"
            }} = Agent.cmd(before, source)
  end
end
