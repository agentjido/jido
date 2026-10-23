defmodule JidoTest.AgentServer.DurableTurn.WaitIntegrationTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server.durable_turn", async: false
  @moduletag :tmp_dir
  alias Jido.AgentServer, as: Server
  alias JidoTest.DurableFixtures.Probe

  defmodule Approval do
    use Jido.Flow,
      name: "core_wait_approval",
      schema: Zoi.object(%{request_id: Zoi.string()})

    flow do
      step "before", input <- input() do
        :ok = JidoTest.DurableFixtures.Probe.enter(:before_wait)
        {:ok, input}
      end

      selection "decision" do
        needs ["before"]
        await("approved", event: "approved", match: %{request_id: input(:request_id)})
        timer("expired", after_ms: 3_600_000)
      end

      step "finish", decision <- result("decision") do
        :ok = JidoTest.DurableFixtures.Probe.enter(:after_wait)
        {:ok, %{count: if(decision.selected == "approved", do: 1, else: -1)}}
      end

      output result("finish")
    end
  end

  defmodule Fault do
    use GenServer
    def start_link(owner), do: GenServer.start_link(__MODULE__, owner, name: __MODULE__)
    def init(owner), do: {:ok, {owner, nil}}
    def arm(stage, mode), do: GenServer.call(__MODULE__, {:arm, stage, mode})
    def check(stage), do: GenServer.call(__MODULE__, {:check, stage})
    def handle_call({:arm, stage, mode}, _, {owner, _}), do: {:reply, :ok, {owner, {stage, mode}}}

    def handle_call({:check, stage}, _, {owner, {stage, mode}}),
      do: {:reply, mode, {owner, nil}}

    def handle_call({:check, _}, _, state), do: {:reply, :pass, state}
  end

  defmodule FaultStorage do
    @behaviour Jido.Persistence.Adapter
    def get(key, opts), do: Jido.Persistence.File.get(key, opts)

    def compare_and_swap(key, expected, bytes, opts) do
      stage =
        case :erlang.binary_to_term(bytes) do
          %{fmt: 1, log: log} when is_list(log) ->
            types =
              for %Runic.Workflow.Fact{value: %{type: type}} <-
                    Runic.Workflow.from_events(log) |> Runic.Workflow.facts(),
                  do: type

            cond do
              :jido_wait_resolution in types -> :resolution
              :jido_wait_input in types -> :acceptance
              true -> :other
            end

          %{server_turn: %{status: :running}} ->
            :hibernation

          _ ->
            :other
        end

      case Fault.check(stage) do
        :reject ->
          {:error, {:rejected, :offline}}

        :conflict ->
          {:error, :conflict}

        :lost ->
          :ok = Jido.Persistence.File.compare_and_swap(key, expected, bytes, opts)
          {:error, :timeout}

        :pass ->
          Jido.Persistence.File.compare_and_swap(key, expected, bytes, opts)
      end
    end
  end

  defmodule ImmediateTimer do
    use Jido.Flow, name: "core_wait_timer"

    flow do
      timer("expired", after_ms: 0)

      step "finish", _expired <- result("expired") do
        {:ok, %{count: -1}}
      end

      output result("finish")
    end
  end

  defmodule LongTimer do
    use Jido.Flow, name: "core_long_wait"

    flow do
      timer("delay", after_ms: 7_776_000_000)

      step "finish", _expired <- result("delay") do
        {:ok, %{count: 7}}
      end

      output result("finish")
    end
  end

  defmodule TwoWaits do
    use Jido.Flow, name: "core_two_waits"

    flow do
      await("first", event: "first")
      await("second", event: "second", match: %{value: result("first", :value)})

      step "finish", input <- result("second") do
        {:ok, %{count: input.value}}
      end

      output result("finish")
    end
  end

  defmodule Agent do
    use Jido.Agent, name: "core_wait_agent"

    state do
      schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      route "request", Approval
      route "timer", ImmediateTimer
      route "long_timer", LongTimer
      route "two_waits", JidoTest.AgentServer.DurableTurn.WaitIntegrationTest.TwoWaits

      route "increment" do
        action _input, context: context do
          {:ok, %{count: context.agent_state.count + 1}}
        end
      end
    end
  end

  setup do
    start_supervised!({Probe, self()})
    :ok
  end

  defp start(c, type \\ "request", adapter \\ Jido.Persistence.File, opts \\ []) do
    id = unique_id("wait")
    persistence = {adapter, path: c.tmp_dir}

    assert {:ok, server} =
             Jido.start_agent(
               c.jido,
               Agent,
               Keyword.merge([id: id, persistence: persistence], opts)
             )

    assert :ok = Server.await_ready(server)
    pending = Server.submit(server, signal(type, %{request_id: "one"}))
    {id, server, pending, persistence}
  end

  defp waiting(server) do
    eventually(fn ->
      case Server.status(server) do
        %{active: %{stage: :waiting}, waits: [_ | _]} = status -> status
        _ -> nil
      end
    end)
  end

  @tag obligation: ["jido.agent_server.durable_turn.I6", "jido.agent_server.durable_turn.I7"]
  test "one Turn releases its Worker, keeps reads and queued Turns, and accepts a Signal", c do
    {_id, server, pending, _} = start(c)
    status = waiting(server)
    [wait] = status.waits
    assert status.active.worker_pid == nil
    assert Server.agent(server).state == %{count: 0}
    queued = Server.submit(server, signal("increment"))
    eventually(fn -> Server.status(server).admission.postponed == 1 end)

    assert {:error, %{details: %{reason: :unmatched_input}}} =
             Server.deliver_wait(server, wait.id, signal("approved", %{request_id: "wrong"}))

    assert :ok = Server.deliver_wait(server, wait.id, signal("approved", %{request_id: "one"}))
    assert {:ok, %{state: %{count: 1}}, []} = Server.await(pending)
    assert {:ok, %{state: %{count: 2}}, []} = Server.await(queued)
    assert Probe.records() == [:before_wait, :after_wait]
  end

  @tag obligation: "jido.agent_server.durable_turn.I6"
  test "hibernation restores the same wait and deadline without repeating completed steps", c do
    {id, server, pending, persistence} = start(c)
    status = waiting(server)
    [wait] = status.waits
    assert :ok = Server.hibernate(server)
    assert {:error, _} = Server.await(pending)
    assert {:ok, awake} = Jido.thaw(c.jido, Agent, id, persistence: persistence)
    assert :ok = Server.await_ready(awake)
    restored = waiting(awake)
    assert restored.active.turn_id == status.active.turn_id
    assert restored.waits == [wait]
    assert Probe.records() == [:before_wait]
    assert :ok = Server.deliver_wait(awake, wait.id, signal("approved", %{request_id: "one"}))
    assert :ok = Server.quiesce(awake)
    assert Server.agent(awake).state == %{count: 1}
  end

  @tag obligation: "jido.agent_server.durable_turn.I10"
  test "cancellation saves a terminal receipt and rejects late wait input", c do
    {_id, server, pending, _} = start(c)
    status = waiting(server)
    [wait] = status.waits
    assert :ok = Server.cancel_turn(server, status.active.turn_id)
    assert {:error, _} = Server.await(pending)
    assert Server.status(server).durable_turn.status == :cancelled

    assert {:error, :not_waiting} =
             Server.deliver_wait(server, wait.id, signal("approved", %{request_id: "one"}))

    assert Server.agent(server).state == %{count: 0}
  end

  @tag obligation: "jido.agent_server.durable_turn.I8"
  test "a timer resumes the same Flow without a decision Signal", c do
    {_id, _server, pending, _} = start(c, "timer")
    assert {:ok, %{state: %{count: -1}}, []} = Server.await(pending)
    assert Probe.records() == []
  end

  for stage <- [:acceptance, :resolution], mode <- [:reject, :lost, :conflict] do
    @tag obligation: ["jido.agent_server.durable_turn.I7", "jido.agent_server.durable_turn.I8"]
    test "#{stage} #{mode} stops before downstream work and restores authoritative data", c do
      start_supervised!({Fault, self()})
      {id, server, pending, persistence} = start(c, "request", FaultStorage)
      %{waits: [wait]} = waiting(server)
      :ok = Fault.arm(unquote(stage), unquote(mode))
      monitor = Process.monitor(server)
      event = signal("approved", %{request_id: "one"})
      result = Server.deliver_wait(server, wait.id, event)

      if unquote(stage) == :acceptance,
        do: assert({:error, _} = result),
        else: assert(result == :ok)

      assert_receive {:DOWN, ^monitor, :process, ^server, _}, 5_000
      assert {:error, _} = Server.await(pending)
      assert Probe.records() == [:before_wait]
      assert {:ok, awake} = Jido.thaw(c.jido, Agent, id, persistence: persistence)
      assert :ok = Server.await_ready(awake)

      if unquote(stage) == :acceptance and unquote(mode) != :lost do
        assert waiting(awake).waits == [wait]
        assert :ok = Server.deliver_wait(awake, wait.id, event)
      end

      assert :ok = Server.quiesce(awake)
      assert Server.agent(awake).state == %{count: 1}
      assert Probe.records() == [:before_wait, :after_wait]
    end
  end

  @tag obligation: ["jido.agent_server.durable_turn.I5", "jido.agent_server.durable_turn.I6"]
  test "AgentServer loss restores a pending wait without rerunning Actions", c do
    {id, server, pending, _} = start(c)
    status = waiting(server)
    monitor = Process.monitor(server)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^server, :killed}, 5_000

    restored =
      eventually(fn ->
        case Jido.whereis_agent(c.jido, id) do
          pid when is_pid(pid) and pid != server -> pid
          _ -> nil
        end
      end)

    assert :ok = Server.await_ready(restored)
    assert waiting(restored).waits == status.waits
    assert {:error, _} = Server.await(pending)
    assert Probe.records() == [:before_wait]
    assert :ok = Server.cancel(restored)
  end

  @tag obligation: "jido.agent_server.durable_turn.I8"
  test "a 90-day timer rearms bounded wakes without resetting the saved deadline", c do
    {_id, server, pending, _} =
      start(c, "long_timer", Jido.Persistence.File, turn_timeout: :infinity)

    status = waiting(server)
    {_, %{active: active}} = :sys.get_state(server)
    assert Process.read_timer(active.wait_timer) <= 4_294_967_295
    send(server, {:wait_wake, active.turn_id, active.wait_token})

    eventually(fn ->
      {_, %{active: next}} = :sys.get_state(server)

      next.wait_token != active.wait_token and next.operation == nil and
        Server.status(server).phase == :waiting
    end)

    assert Server.status(server).waits == status.waits
    assert :ok = Server.cancel(server)
    assert {:error, _} = Server.await(pending)
  end

  @tag obligation: "jido.agent_server.durable_turn.I7"
  test "saved input IDs make retries inert while a later wait remains pending", c do
    {_id, server, pending, _} = start(c, "two_waits")
    %{waits: [first]} = waiting(server)
    event = signal("first", %{value: 7})
    assert :ok = Server.deliver_wait(server, first.id, event)
    %{waits: [second]} = waiting(server)
    assert second.id != first.id
    assert :ok = Server.deliver_wait(server, first.id, event)
    assert waiting(server).waits == [second]

    assert {:error, %{details: %{reason: :conflicting_input_id}}} =
             Server.deliver_wait(server, first.id, %{event | data: %{value: 8}})

    assert :ok = Server.deliver_wait(server, second.id, signal("second", %{value: 7}))
    assert {:ok, %{state: %{count: 7}}, []} = Server.await(pending)
  end

  @tag obligation: "jido.agent_server.durable_turn.I11"
  test "ordinary AgentServer execution rejects waits before Actions and rejects host spoofing",
       c do
    assert {:ok, server} = Jido.start_agent(c.jido, Agent, id: unique_id("ordinary"))
    assert :ok = Server.await_ready(server)
    request = signal("request", %{request_id: "one"})

    assert {:error, %{details: %{reason: :unsupported_host, capability: :waits}}} =
             Server.call(server, request)

    assert Probe.records() == []

    for key <- [:__jido_wait_host__, :__jido_wait_result__, :__jido_exec_durable__] do
      assert {:error, _} = Server.call(server, request, context: %{key => %{now: 0}})
    end

    assert Probe.records() == []
  end

  @tag obligation: ["jido.agent_server.durable_turn.I6", "jido.agent_server.durable_turn.I7"]
  test "quiesce can finish its accepted Turn through addressed wait input", c do
    {_id, server, pending, _} = start(c)
    %{waits: [wait]} = waiting(server)
    control = Task.async(fn -> Server.quiesce(server) end)
    eventually(fn -> Server.status(server).admission.mode == :quiescing end)
    assert :ok = Server.deliver_wait(server, wait.id, signal("approved", %{request_id: "one"}))
    assert :ok = Task.await(control)
    assert {:ok, %{state: %{count: 1}}, []} = Server.await(pending)
    assert Server.status(server).admission.mode == :quiesced
  end

  for mode <- [:reject, :lost, :conflict] do
    @tag obligation: "jido.agent_server.durable_turn.I6"
    test "hibernation #{mode} preserves the pending graph and enforces safe admission", c do
      start_supervised!({Fault, self()})
      {id, server, pending, persistence} = start(c, "request", FaultStorage)
      %{waits: [wait]} = waiting(server)
      :ok = Fault.arm(:hibernation, unquote(mode))
      assert {:error, %{resumable?: safe?}} = Server.hibernate(server)
      assert safe? == (unquote(mode) == :reject)
      assert waiting(server).waits == [wait]
      event = signal("approved", %{request_id: "one"})

      if safe? do
        assert :ok = Server.deliver_wait(server, wait.id, event)
        assert {:ok, %{state: %{count: 1}}, []} = Server.await(pending)
      else
        assert {:error, :unsafe_resume} = Server.resume(server)
        assert {:error, :unsafe_resume} = Server.cancel(server)
        assert {:error, :not_waiting} = Server.deliver_wait(server, wait.id, event)
        assert :ok = Jido.stop_agent(c.jido, server)
        assert {:error, _} = Server.await(pending)
        assert {:ok, awake} = Jido.thaw(c.jido, Agent, id, persistence: persistence)
        assert :ok = Server.await_ready(awake)
        assert waiting(awake).waits == [wait]
        assert :ok = Server.deliver_wait(awake, wait.id, event)
        assert :ok = Server.quiesce(awake)
        assert Server.agent(awake).state == %{count: 1}
      end

      assert Probe.records() == [:before_wait, :after_wait]
    end
  end
end
