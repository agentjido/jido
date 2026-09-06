defmodule JidoTest.Examples.Factory.FlowFactoryTest do
  use JidoTest.Case, async: true
  @moduletag :example

  @moduletag timeout: 120_000
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Factory.FlowFactory
  alias FlowFactory.{Contract, Mission, Worker}
  alias JidoTest.FactoryHTTP, as: HTTP

  test "real workers overlap, join actual artifacts, repair, and deliver the reviewed revision",
       c do
    {mission, id} = start!(c, context: observed(true))
    roots = take_roles(["research", "design"], 0)
    assert FlowFactory.status(mission).status == :running
    assert FlowFactory.status(mission).output == %{}
    assert_eventually(Server.status(mission).phase == :idle)
    release(roots, "design")
    refute_receive {:work, %{role: "api"}, _}
    release(roots, "research")

    components = take_roles(["api", "ui", "test"], 0)

    for {_, {_, input}} <- components do
      assert input.inputs.discovery.research.role == "research"
      assert input.inputs.discovery.design.role == "design"
    end

    release(components, "test")
    release(components, "ui")
    refute_receive {:work, %{role: "integration"}, _}
    release(components, "api")

    integration = take_roles(["integration"], 0)
    {_, input} = integration["integration"]
    assert Enum.map(input.inputs.components, & &1.role) == ["api", "ui", "test"]
    release(integration, "integration")

    reviews = take_roles(["quality", "security"], 0)

    # Worker readiness does not acknowledge the mission's asynchronous progress commit.
    assert_eventually(Map.has_key?(FlowFactory.status(mission).artifacts, "#{id}/integration/0"))

    for {_, {_, input}} <- reviews do
      assert input.inputs.package == FlowFactory.status(mission).artifacts["#{id}/integration/0"]
    end

    release(reviews, "security")
    refute_receive {:work, %{revision: 1}, _}
    release(reviews, "quality")

    repairs = take_roles(["api", "ui", "test"], 1)

    for {_, {_, input}} <- repairs do
      assert input.inputs.findings == ["Add an explicit empty-export acceptance case."]
      assert input.inputs.previous_package.revision == 0
    end

    release_all(repairs)
    release_all(take_roles(["integration"], 1))
    release_all(take_roles(["quality", "security"], 1))
    handoff = take_roles(["delivery"], 1)
    {_, input} = handoff["delivery"]
    assert input.inputs.review.accepted
    assert input.inputs.package.revision == 1
    release_all(handoff)

    state = terminal(mission, :completed)
    assert state.output.repairs == 1
    assert state.output.mission.revision == 1
    assert map_size(state.artifacts) == 15
    assert length(state.events) == 30
    assert Enum.all?(state.assignments, fn {_, status} -> status == :completed end)
    assert state.output.handoff == state.artifacts["#{id}/delivery/1"]
    assert_workers_stopped(c.jido, id)
  end

  test "initial acceptance skips repair and Choice omits an unrequested security review", c do
    {mission, id} = start!(c, security: false, context: %{accept_after: 0})
    state = terminal(mission, :completed)
    assert state.output.repairs == 0
    assert state.output.mission.review.security.skipped
    assert map_size(state.artifacts) == 8
    refute Enum.any?(state.events, &(&1.role == "security" or &1.revision > 0))
    assert_workers_stopped(c.jido, id)
  end

  test "the final permitted repair can succeed", c do
    {mission, _} = start!(c, context: %{accept_after: 2})
    state = terminal(mission, :completed)
    assert state.output.repairs == 2
    assert state.output.handoff.revision == 2
    assert map_size(state.artifacts) == 21
  end

  test "repair exhaustion fails without delivery and keeps previously committed artifacts", c do
    {mission, id} = start!(c, context: %{accept_after: 3})
    state = terminal(mission, :failed)
    assert state.output == %{}
    assert state.error != ""
    assert map_size(state.artifacts) == 20
    assert state.artifacts["#{id}/quality/2"].verdict == :changes_required
    refute Enum.any?(state.events, &(&1.role == "delivery" or &1.revision > 2))
    assert_workers_stopped(c.jido, id)
  end

  test "worker failure prevents dependent integration and delivery", c do
    {mission, id} = start!(c, context: %{fail_role: "api"})
    state = terminal(mission, :failed)
    assert state.artifacts["#{id}/research/0"].role == "research"
    assert state.artifacts["#{id}/design/0"].role == "design"
    refute Enum.any?(state.events, &(&1.role in ["integration", "delivery"]))
    assert_workers_stopped(c.jido, id)
  end

  test "cancel stops active worker execution and rejects later results", c do
    {mission, id} = start!(c, context: observed(true))
    roots = take_roles(["research", "design"], 0)
    monitors = monitor_calls(roots)
    assert {:ok, agent} = FlowFactory.cancel(mission)
    assert agent.state.status == :cancelled
    assert_calls_stopped(monitors)
    assert_workers_stopped(c.jido, id)
    assert {:error, _} = Server.call(mission, finished(id, %{}))
    assert FlowFactory.status(mission).status == :cancelled
    assert FlowFactory.status(mission).output == %{}
    refute_receive {:work, %{role: "api"}, _}
  end

  test "owner shutdown stops workers during a nested repair Flow", c do
    context = observed(fn input -> input.revision == 1 end)
    {mission, id} = start!(c, context: context)
    # Wait for the first cycle before the held repair wave. Each group has its own bound.
    take_roles(["research", "design"], 0)
    take_roles(["api", "ui", "test"], 0)
    take_roles(["integration"], 0)
    take_roles(["quality", "security"], 0)
    repairs = take_roles(["api", "ui", "test"], 1)
    monitors = monitor_calls(repairs)
    assert :ok = Jido.stop_agent(c.jido, mission)
    assert_calls_stopped(monitors)
    assert_workers_stopped(c.jido, id)
  end

  test "the complete Flow deadline stops pending work and releases workers", c do
    {mission, id} = start!(c, context: Map.put(observed(true), :flow_timeout, 500))
    state = terminal(mission, :failed)
    assert state.error =~ "timed out"
    assert_workers_stopped(c.jido, id)
    refute_receive {:work, %{role: "api"}, _}
  end

  test "a worker crash fails the mission and stops the other active worker", c do
    {mission, id} = start!(c, context: observed(true))
    roots = take_roles(["research", "design"], 0)
    monitors = monitor_calls(roots)
    Process.exit(Jido.whereis_agent(c.jido, "#{id}/research"), :kill)
    terminal(mission, :failed)
    assert_calls_stopped(monitors)
    assert_workers_stopped(c.jido, id)
  end

  test "wrong mission results and duplicate submissions do not replace active work", c do
    {mission, _} = start!(c, context: observed(true))
    roots = take_roles(["research", "design"], 0)
    assert_eventually(length(FlowFactory.status(mission).events) == 2)
    before = FlowFactory.status(mission)
    assert {:error, _} = Server.call(mission, finished("different-mission", %{}))
    assert {:error, _} = Mission.start(mission, "Another goal")
    assert FlowFactory.status(mission) == before
    assert {:ok, _} = FlowFactory.cancel(mission)
    assert_calls_stopped(monitor_calls(roots))
  end

  test "worker retries use the committed result and reject changed inputs", c do
    {:ok, worker} = Jido.start_agent(c.jido, Worker, initial_state: %{role: "research"})
    input = %{mission_id: "one", role: "research", revision: 0, goal: "CSV export", inputs: %{}}
    request = signal("factory.flow.work", input)
    context = observed(false)
    assert {:ok, first} = Server.call(worker, request, context: context)
    assert_receive {:work, ^input, _}
    assert {:ok, second} = Server.call(worker, request, context: context)
    assert first == second
    refute_receive {:work, _, _}

    assert {:error, _} =
             Server.call(worker, signal("factory.flow.work", %{input | goal: "Changed"}))

    assert Server.snapshot(worker).agent == first
  end

  test "invalid goals start no workers and cannot leave a running mission", c do
    id = unique_id("invalid-flow")
    assert {:error, _} = FlowFactory.start(c.jido, "   ", id: id)
    assert Jido.whereis_agent(c.jido, id) == nil
    assert_workers_stopped(c.jido, id)
  end

  test "live mode uses real ReqLLM requests and validates review JSON without a key", c do
    observer = self()

    context =
      HTTP.context(fn body ->
        request = body["messages"] |> List.last() |> Map.fetch!("content")
        text = if is_binary(request), do: request, else: Enum.map_join(request, & &1["text"])
        input = Jason.decode!(text)
        send(observer, {:http_work, input["role"]})

        if input["role"] in ["quality", "security"],
          do:
            HTTP.text(
              Jason.encode!(%{text: "Reviewed proposal", verdict: "accepted", findings: []})
            ),
          else: HTTP.text("Live-path #{input["role"]} artifact")
      end)
      |> Map.put(:mode, :live)

    {mission, _} = start!(c, context: context)
    state = terminal(mission, :completed)
    assert state.output.repairs == 0
    assert state.output.handoff.text == "Live-path delivery artifact"
    for role <- Contract.roles(), do: assert_received({:http_work, ^role})
    refute inspect(state) =~ "fixture-key"
    assert portable?(state)
  end

  test "invalid live review output stops the Flow before handoff", c do
    context = HTTP.context(fn _ -> HTTP.text("not a JSON review") end) |> Map.put(:mode, :live)
    {mission, id} = start!(c, context: context)
    state = terminal(mission, :failed)
    assert state.output == %{}
    refute Enum.any?(state.events, &(&1.role == "delivery"))
    assert_workers_stopped(c.jido, id)
  end

  defp start!(c, opts) do
    id = unique_id("flow-factory")
    {:ok, mission} = FlowFactory.start(c.jido, "Design CSV export", Keyword.put(opts, :id, id))
    {mission, id}
  end

  defp observed(hold) do
    observer = self()

    %{
      on_worker: fn input, pid ->
        send(observer, {:work, input, pid})

        if hold == true or (is_function(hold, 1) and hold.(input)) do
          receive do
            :release -> :ok
          after
            15_000 -> raise "Worker test barrier was not released"
          end
        end
      end
    }
  end

  defp take_roles(roles, revision) do
    Map.new(roles, fn role ->
      assert_receive {:work, %{role: ^role, revision: ^revision} = input, pid}, 10_000
      {role, {pid, input}}
    end)
  end

  defp release(workers, role), do: send(elem(workers[role], 0), :release)
  defp release_all(workers), do: Enum.each(workers, fn {role, _} -> release(workers, role) end)

  defp monitor_calls(workers),
    do: Enum.map(workers, fn {_, {pid, _}} -> {Process.monitor(pid), pid} end)

  defp assert_calls_stopped(monitors) do
    for {ref, pid} <- monitors, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 3_000)
  end

  defp terminal(mission, expected) do
    eventually(
      fn ->
        state = FlowFactory.status(mission)
        if state.status != :running, do: state
      end,
      timeout: 90_000,
      interval: 50
    )
    |> then(fn state ->
      assert state.status == expected, inspect(state.error)
      state
    end)
  end

  defp assert_workers_stopped(jido, id) do
    assert_eventually(
      Enum.all?(Contract.roles(), &(Jido.whereis_agent(jido, "#{id}/#{&1}") == nil))
    )
  end

  defp finished(id, output),
    do:
      signal("factory.flow.finished", %{
        mission_id: id,
        status: :completed,
        output: output,
        error: ""
      })

  defp portable?(value)
       when is_pid(value) or is_reference(value) or is_function(value) or is_port(value),
       do: false

  defp portable?(value) when is_map(value),
    do: Enum.all?(value, fn {key, item} -> portable?(key) and portable?(item) end)

  defp portable?(value) when is_list(value), do: Enum.all?(value, &portable?/1)
  defp portable?(value) when is_tuple(value), do: value |> Tuple.to_list() |> portable?()
  defp portable?(_), do: true
end
