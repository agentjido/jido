Code.require_file("../support/fuzz.exs", __DIR__)

defmodule Jido.AgentServer.Property.LifecycleModelTest do
  use Jido.Test.Case, async: false

  @moduletag :tmp_dir

  alias Jido.AgentServer, as: Server
  alias Jido.Test.Property.Fuzz

  defmodule Add do
    use Jido.Flow, name: "runtime_property_add"

    flow do
      step "add", _input <- input(), inline: [context: context] do
        state = context.agent_state
        {:ok, %{state | count: state.count + 1, history: state.history ++ [1]}}
      end

      output result("add")
    end
  end

  defmodule Mutate do
    use Jido.Action,
      name: "runtime_property_mutate",
      schema:
        Jido.Joi.object(%{
          mode: Jido.Joi.enum([:success, :failure, :invalid_state, :invalid_directive]),
          by: Jido.Joi.integer()
        })

    @impl true
    def run(%{mode: :success, by: by}, %{agent_state: state}) do
      {:ok, %{state | count: state.count + by, history: state.history ++ [by]}}
    end

    def run(%{mode: :failure}, _context),
      do: {:error, Jido.Error.execution_error("generated failure")}

    def run(%{mode: :invalid_state}, %{agent_state: state}),
      do: {:ok, %{state | count: "invalid"}}

    def run(%{mode: :invalid_directive}, %{agent_state: state}),
      do: {:ok, state, [:invalid]}
  end

  defmodule Counter do
    use Jido.Agent, name: "runtime_property_counter"

    state do
      schema Jido.Joi.object(%{
               count: Jido.Joi.integer() |> Jido.Joi.default(0),
               history: Jido.Joi.list(Jido.Joi.integer()) |> Jido.Joi.default([])
             })
    end

    routes do
      route "runtime.property.add", Add
      route "runtime.property.mutate", Mutate
    end
  end

  defmodule Team do
    use Jido.Agent, name: "runtime_property_team"

    topology do
      agent :worker, Counter
    end

    routes do
      route "runtime.property.send" do
        action input, context: context do
          signal = Jido.Signal.new!("runtime.property.add", input, source: "/property")
          directive = Jido.Agent.Directive.emit(signal, {:durable, {:agent, :worker, 1}})
          {:ok, context.agent_state, [directive]}
        end
      end
    end
  end

  for {suite, runs} <- [{:property, 30}, {:fuzz, 300}] do
    @tag [
      {suite, true},
      fuzz_id: "agent_server_lifecycle",
      max_runs: runs,
      max_run_time: 120_000,
      max_shrinking_steps: 12,
      timeout: 180_000
    ]
    test "#{suite} generated histories preserve commit, recovery, and cleanup", c do
      step =
        StreamData.fixed_map(%{
          "mode" => StreamData.member_of(~w(success failure invalid_state invalid_directive)),
          "by" => StreamData.integer(-100..100)
        })

      generator =
        StreamData.fixed_map(%{
          "initial_count" => StreamData.integer(-1_000..1_000),
          "steps" => StreamData.list_of(step, max_length: 20),
          "topology" => StreamData.list_of(StreamData.member_of(~w(submit retry remove crash restore)), max_length: 8)
        })

      examples = [
        %{
          "initial_count" => 0,
          "topology" => ~w(submit retry remove crash restore submit retry),
          "steps" =>
            for(
              mode <- ~w(success failure invalid_state invalid_directive),
              do: %{"mode" => mode, "by" => 1}
            )
        }
      ]

      Fuzz.check(
        "agent_server_lifecycle",
        generator,
        Map.to_list(c) ++ [examples: examples],
        fn %{"initial_count" => initial_count, "steps" => steps, "topology" => topology} ->
          verify_history(c, initial_count, steps, topology)
        end
      )
    end
  end

  defp verify_history(c, initial_count, steps, topology) do
    id = unique_id("runtime-property")
    path = Path.join(c.tmp_dir, id)
    persistence = {Jido.Persistence.File, path: path}
    c = Jido.Test.Case.restart_jido!(c, persistence)

    {:ok, server} =
      Jido.Test.AgentServer.Assertions.start_agent(c.jido, Counter,
        id: id,
        state: %{count: initial_count},
        persistence_mode: :create
      )

    {expected, observations} =
      Enum.reduce(steps, {%{count: initial_count, history: []}, MapSet.new()}, fn step, {model, observations} ->
        mode = String.to_existing_atom(step["mode"])
        result = Server.call(server, signal("runtime.property.mutate", %{mode: mode, by: step["by"]}))

        next_model =
          case step do
            %{"mode" => "success", "by" => by} ->
              expected = %{count: model.count + by, history: model.history ++ [by]}
              assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} = result
              assert Server.snapshot(server).agent.state == expected
              expected

            %{"mode" => mode} when mode in ~w(failure invalid_state invalid_directive) ->
              assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: error}} = result
              assert is_exception(error)
              model
          end

        assert Server.snapshot(server).agent.state == next_model
        {next_model, MapSet.put(observations, step["mode"])}
      end)

    assert Server.snapshot(server).agent.state == expected
    monitor = Process.monitor(server)
    assert {:ok, %Jido.AgentServer.Snapshot{}} = Server.stop(server)
    assert_receive {:DOWN, ^monitor, :process, ^server, _reason}, 5_000
    assert Jido.whereis_agent(c.jido, id) == nil

    assert {:ok, restored} = Jido.thaw(c.jido, Counter, id)
    assert :ok = Server.await_ready(restored)
    assert Server.snapshot(restored).agent.state == expected
    assert :ok = Jido.stop_agent(c.jido, restored)
    assert Jido.whereis_agent(c.jido, id) == nil
    assert Jido.resident_agent_count(c.jido) == 0

    verify_topology(c, persistence, topology)
    ["hibernate", "restore", "cleanup" | topology ++ MapSet.to_list(observations)]
  end

  defp verify_topology(_context, _store, []), do: :ok

  defp verify_topology(c, store, steps) do
    {:ok, owner} = Jido.agent_address(c.jido, "property-team")
    member = %{owner | id: "property-team/$topology/worker/1/initial"}
    assert {:ok, ^owner} = Jido.create_agent(c.jido, owner, Team)
    assert {:ok, root} = Jido.activate_agent(c.jido, owner)

    data = %{instance: c.jido, owner: owner, member: member, store: store}
    model = %{root: root, owned?: true, accepted: 0, crashed?: false}

    model =
      Enum.reduce(steps, model, fn step, model ->
        next = topology_step(step, model, data)
        verify_topology_model(next, data)
        next
      end)

    assert :ok = Jido.stop_agent(c.jido, model.root)
  end

  defp topology_step("submit", model, data) do
    request = Server.submit(model.root, signal("runtime.property.send"))
    status = if model.owned?, do: :committed, else: :failed
    assert {:ok, %{status: ^status}} = Server.await(request, 3_000)

    if model.owned? do
      expected = model.accepted + 1

      eventually(
        fn ->
          {:ok, member} = Jido.resolve_agent(data.instance, data.member)
          Server.snapshot(member).agent.state.count == expected
        end,
        timeout: 3_000
      )

      # Acceptance can finish before the sender gets its reply and clears the outbox.
      eventually(fn -> match?(%{topology_handoffs: %{pending: 0}}, Server.status(model.root)) end, timeout: 3_000)
      %{model | accepted: expected}
    else
      model
    end
  end

  defp topology_step("retry", model, data) do
    if model.owned? and model.accepted > 0 do
      assert {:ok, member} = Jido.resolve_agent(data.instance, data.member)
      [id | _] = Map.keys(receipts(data))
      expired = {node(), System.monotonic_time(:millisecond) - 1}
      retry = {:accept_topology_handoff, id, data.member, signal("runtime.property.add"), expired}
      assert :accepted = :gen_statem.call(member, retry)
    end

    model
  end

  defp topology_step("remove", model, _data) do
    assert :ok = Server.remove_topology_member(model.root, :worker, 1)
    %{model | owned?: false}
  end

  defp topology_step("crash", %{crashed?: true} = model, _data), do: model

  defp topology_step("crash", model, data) do
    old = model.root
    Process.exit(old, :kill)

    root =
      eventually(
        fn ->
          case Jido.resolve_agent(data.instance, data.owner) do
            {:ok, pid} when pid != old -> pid
            _ -> nil
          end
        end,
        timeout: 2_000
      )

    assert :ok = Server.await_ready(root)
    %{model | root: root, crashed?: true}
  end

  defp topology_step("restore", model, data) do
    assert :ok = Jido.stop_agent(data.instance, model.root)
    assert {:error, :topology_owner_required} = Jido.activate_agent(data.instance, data.member)
    assert {:ok, root} = Jido.activate_agent(data.instance, data.owner)
    %{model | root: root, owned?: true, crashed?: false}
  end

  defp verify_topology_model(model, data) do
    assert %{queue_depth: 0} = Server.status(model.root)
    assert map_size(receipts(data)) == min(model.accepted, 1)

    if model.owned? do
      assert {:ok, member} = Jido.resolve_agent(data.instance, data.member)
      assert %{queue_depth: 0} = Server.status(member)
      eventually(fn -> Server.snapshot(member).agent.state.count == model.accepted end)
    else
      assert {:error, :topology_member_removed} = Jido.activate_agent(data.instance, data.member)
    end
  end

  defp receipts(data) do
    {:ok, bytes, _condition} = Jido.Persistence.Store.read(data.store, Jido.Persistence.agent_key(data.member))
    {:ok, record} = Jido.Persistence.Record.decode(bytes)
    Jido.Persistence.Record.topology_handoffs(record).accepted
  end
end
