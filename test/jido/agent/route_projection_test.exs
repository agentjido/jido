defmodule Jido.Agent.RouteProjectionTest do
  use Jido.Test.Case, async: true

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
        Jido.Joi.object(%{
          state: Jido.Joi.any() |> Jido.Joi.optional(),
          reply: Jido.Joi.any() |> Jido.Joi.optional()
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
      output_schema: Jido.Joi.object(%{value: Jido.Joi.integer()})

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
        Jido.Joi.object(%{
          state: Jido.Joi.map(),
          reply: Jido.Joi.any()
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
    def state_spec(_opts), do: {:reply_reductions, Jido.Joi.integer() |> Jido.Joi.default(0)}

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
      schema: Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)}),
      routes: routes,
      plugins: extensions
    })
    |> Agent.instantiate!(id: Jido.Id.uuid7())
  end

  defp request(data \\ %{}) do
    signal = Signal.new!("project", data, source: "/test")
    {:ok, signal, trace} = Signal.Context.ensure_trace(signal)
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
    reply_trace = Signal.Context.get_trace(reply)
    assert %{reply_trace | causation_id: nil} == trace
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
            %Jido.Error.ValidationError{
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

    expected_error = %Jido.Error.ValidationError{
      code: :missing_output_field,
      path: [:state, :path, 0],
      message: "Selected output field is missing",
      details: %{key: :state}
    }

    assert {:error, ^expected_error} = Agent.cmd(before, source)
    assert before.state == %{count: 0}

    assert {:ok, server} = Jido.Test.AgentServer.Assertions.start_agent(jido, before)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: ^expected_error}} =
             AgentServer.call(server, source)

    assert AgentServer.snapshot(server).agent === before
    assert AgentServer.status(server).agent_revision == 0
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
      assert {:error, %Jido.Error.ValidationError{}} = Agent.cmd(before, source)
    end

    assert before.state == %{count: 0}
  end

  test "a manual Reply and a generated Reply fail the complete batch" do
    before = agent([project_route()])
    {source, trace} = request(%{reply: %{value: 1}})

    manual_signal = Signal.new!("manual.done", %{}, source: "/manual")

    {:ok, manual_signal} =
      Signal.Context.put_trace(manual_signal, Jido.Trace.with_causation(trace, source.id))

    manual = Directive.reply(manual_signal)
    source = %{source | data: Map.put(source.data, :directives, [manual])}

    assert {:error,
            %Jido.Error.ValidationError{
              message: "Agent turn can return only one Reply Directive"
            }} = Agent.cmd(before, source)

    assert before.state == %{count: 0}
  end

  test "direct and live execution use the same projection path", %{jido: jido} do
    before = agent([project_route()])
    {source, _trace} = request(%{reply: %{value: 1}})

    assert {:ok, direct, [%Reply{signal: direct_reply}]} = Agent.cmd(before, source)
    assert {:ok, server} = Jido.Test.AgentServer.Assertions.start_agent(jido, before)

    assert {:ok,
            %Jido.AgentServer.TurnResult{
              status: :committed,
              reply: %Signal{} = live_reply
            }} = AgentServer.call(server, source)

    live = AgentServer.snapshot(server).agent

    assert live === direct
    assert Signal.get_context(live_reply, "jidocausationid") == source.id

    normalize = fn signal ->
      signal
      |> Map.from_struct()
      |> Map.drop([:id])
      |> Map.update!(:extensions, &Map.delete(&1, "traceparent"))
    end

    assert normalize.(live_reply) == normalize.(direct_reply)
  end

  test "a cast commits generated state and discards its reply", %{jido: jido} do
    before = agent([project_route(), barrier_route()])
    {source, _trace} = request(%{reply: %{value: 1}})
    {:ok, server} = Jido.Test.AgentServer.Assertions.start_agent(jido, before)

    assert :ok = AgentServer.cast(server, source)
    barrier = Signal.new!("barrier", %{}, source: "/test")

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             AgentServer.call(server, barrier)

    barrier_result = AgentServer.snapshot(server).agent
    assert barrier_result.state == %{count: 1}
    assert AgentServer.status(server).agent_revision == 2
  end

  test "cancellation stops output before route projection", %{jido: jido} do
    route = %{
      project_route()
      | handler: %{kind: :action, target: BlockingProject}
    }

    before = agent([route])
    {source, _trace} = request(%{test_pid: self()})
    {:ok, server} = Jido.Test.AgentServer.Assertions.start_agent(jido, before)
    caller = Task.async(fn -> AgentServer.call(server, source) end)

    assert_receive {:route_projection_started, worker}, 1_000
    turn_id = AgentServer.status(server).active_turn_id
    assert :ok = AgentServer.cancel_turn(server, turn_id)
    assert {:ok, %Jido.AgentServer.TurnResult{status: :cancelled}} = Task.await(caller)
    refute Process.alive?(worker)
    assert AgentServer.snapshot(server).agent === before
    assert AgentServer.status(server).agent_revision == 0
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
