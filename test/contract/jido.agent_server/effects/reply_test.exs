Code.require_file("../support.ex", __DIR__)

defmodule JidoTest.AgentServer.Effects.ReplyTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server.effects", async: false

  import JidoTest.Eventually
  alias Jido.Agent
  alias Jido.Agent.Directive
  alias Jido.AgentServer, as: Server
  alias Jido.Signal
  alias JidoTest.AgentServer.Fixtures, as: F

  defmodule Work do
    use Jido.Action,
      name: "server_reply_contract_work",
      output_schema: Zoi.any()

    def run(input, context) do
      if input[:gate] do
        send(context.observer, {:reply_action_waiting, self()})
        receive do: (:release -> :ok)
      end

      {:ok, %{context.agent_state | count: context.agent_state.count + 1}, input.directives}
    end
  end

  setup do
    context = F.setup_runtime()

    agent =
      Agent.define!(%{
        name: "server_reply_contract",
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
        extensions: Agent.definition(context.agent).extensions,
        routes: [
          %{
            path: "reply",
            handler: %{kind: :action, target: Work},
            state: %{source: :output, path: []}
          }
        ]
      })
      |> Agent.instantiate!(id: "server-reply-contract")

    Map.put(context, :agent, agent)
  end

  @tag obligation: "jido.agent_server.effects.I13"
  test "call returns the commit and delivers the unchanged Reply Signal", c do
    server = F.start(c)
    {request, output, reply} = request()

    assert {:ok, %{state: %{count: 1}}, [^reply]} = Server.call(server, request)
    assert_receive ^output, 1_000
    assert_eventually(Server.status(server).phase == :idle)
    assert Server.status(server).last_effect_outcome.status == :succeeded
  end

  @tag obligation: "jido.agent_server.effects.I13"
  test "submit holds Reply Signals until the owner collects the turn result", c do
    server = F.start(c)
    {request, output, reply} = request()
    pending = Server.submit(server, request)

    assert_eventually(Server.status(server).phase == :idle)
    refute_received ^output
    assert {:ok, %{state: %{count: 1}}, [^reply]} = Server.await(pending)
    assert_receive ^output, 1_000
  end

  @tag obligation: "jido.agent_server.effects.I13"
  test "an await timeout keeps a later Reply for the same pending request", c do
    server = F.start(c)
    {request, output, reply} = request(gate: true)
    pending = Server.submit(server, request, context: %{observer: self()})

    assert_receive {:reply_action_waiting, action}, 1_000
    assert {:error, :timeout} = Server.await(pending, 0)
    send(action, :release)
    assert_eventually(Server.status(server).phase == :idle)
    refute_received ^output
    assert {:ok, %{state: %{count: 1}}, [^reply]} = Server.await(pending)
    assert_receive ^output, 1_000
  end

  @tag obligation: "jido.agent_server.effects.I13"
  test "abandon drops buffered and future Reply Signals without cancelling the turn", c do
    server = F.start(c)
    {request, output, _reply} = request(gate: true)
    pending = Server.submit(server, request, context: %{observer: self()})

    assert_receive {:reply_action_waiting, action}, 1_000
    assert :ok = Server.abandon(pending)
    send(action, :release)
    assert :ok = Server.quiesce(server)
    assert Server.agent(server).state.count == 1
    refute_received ^output
  end

  @tag obligation: "jido.agent_server.effects.I13"
  test "abandon drops a Reply that the completed effect already buffered", c do
    server = F.start(c)
    {request, output, _reply} = request()
    pending = Server.submit(server, request)

    assert_eventually(Server.status(server).phase == :idle)
    assert :ok = Server.abandon(pending)
    assert Server.agent(server).state.count == 1
    refute_received ^output
  end

  @tag obligation: "jido.agent_server.effects.I13"
  test "a call timeout drops its later Reply without cancelling the accepted turn", c do
    server = F.start(c)
    {request, output, _reply} = request(gate: true)
    owner = self()

    caller =
      Task.async(fn ->
        result =
          catch_exit(Server.call(server, request, timeout: 20, context: %{observer: owner}))

        send(owner, {:reply_call_timed_out, self(), result})

        receive do
          :inspect_mailbox ->
            receive do
              ^output -> :reply_received
            after
              0 -> :no_reply
            end
        end
      end)

    assert_receive {:reply_action_waiting, action}, 1_000
    assert_receive {:reply_call_timed_out, caller_pid, {:timeout, _}}, 1_000
    assert caller.pid == caller_pid
    send(action, :release)
    assert :ok = Server.quiesce(server)
    send(caller.pid, :inspect_mailbox)
    assert :no_reply = Task.await(caller)
    assert Server.agent(server).state.count == 1
  end

  @tag obligation: "jido.agent_server.effects.I13"
  test "cast rejects Reply before commit because it has no request owner", c do
    server = F.start(c)
    {request, output, _reply} = request()

    assert :ok = Server.cast(server, request)
    assert :ok = Server.quiesce(server)
    assert Server.agent(server) == c.agent
    assert Server.status(server).state_version == 0
    refute_received ^output
  end

  @tag obligation: ["jido.agent_server.effects.I2", "jido.agent_server.effects.I13"]
  test "Reply keeps batch order and does not run after an earlier effect fails", c do
    server = F.start(c, directive_handler: &__MODULE__.effect/2)
    {request, output, reply} = request()
    gate = %F.Effect{label: :before_reply, observer: self(), mode: :gate}
    request = put_in(request.data.directives, [gate, reply])

    assert {:ok, _, [^gate, ^reply]} = Server.call(server, request)
    assert_receive {:reply_effect_waiting, effect}, 1_000
    refute_received ^output
    send(effect, :release)
    assert_receive ^output, 1_000
    assert_eventually(Server.status(server).phase == :idle)

    failed = F.start(c, directive_handler: &__MODULE__.effect/2)
    {request, failed_output, reply} = request()
    failure = %F.Effect{label: :fail, mode: :fail}
    request = put_in(request.data.directives, [failure, reply])
    assert {:ok, _, [^failure, ^reply]} = Server.call(failed, request)
    assert_eventually(Server.status(failed).phase == :idle)
    assert Server.status(failed).last_effect_outcome.status == :failed
    refute_received ^failed_output
  end

  def effect(%F.Effect{mode: :gate, observer: observer}, _context) do
    send(observer, {:reply_effect_waiting, self()})
    receive do: (:release -> :ok)
  end

  def effect(%F.Effect{mode: :fail}, _context), do: {:error, :controlled_failure}

  defp request(opts \\ []) do
    request =
      Signal.new!(
        "reply",
        %{gate: Keyword.get(opts, :gate, false), directives: []},
        source: "/test/reply"
      )

    output = Signal.new!("reply.done", %{request: request.id}, source: "/agent/reply")
    {:ok, output} = Signal.put_context(output, "jidocausationid", request.id)
    reply = Directive.reply(output)
    {%{request | data: %{request.data | directives: [reply]}}, output, reply}
  end
end
