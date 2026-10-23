defmodule JidoTest.AgentServer.DurableTurn.WaitHostTest do
  use ExUnit.Case, async: true
  use Covenant.Case, component: "jido.agent_server.durable_turn", async: true

  alias Jido.AgentServer.DurableTurn.WaitHost
  alias Jido.Exec.{Frame, Waits}
  alias Runic.Workflow
  alias Runic.Workflow.{CausalContext, Fact, Runnable}
  alias Runic.Workflow.Events.FactProduced

  defmodule Approval do
    use Jido.Flow,
      name: "host_policy_approval"

    flow do
      selection "decision" do
        await "approved", event: "approved", match: %{id: input(:id)}
        timer "expired", after_ms: 1_000
      end

      output result("decision")
    end
  end

  defmodule ParallelWaits do
    use Jido.Flow,
      name: "host_policy_parallel_waits"

    flow do
      await "first", event: "first"
      await "second", event: "second"
      output %{first: result("first"), second: result("second")}
    end
  end

  defp waiting(flow \\ Approval) do
    {:ok, workflow} = Jido.Exec.compile(flow)

    workflow
    |> Workflow.put_run_context(%{_global: Waits.context(%{}, "execution", 100)})
    |> Workflow.react_until_satisfied(Frame.new(%{id: 7}))
  end

  defp input(workflow, id \\ "one") do
    [request] = Waits.pending(workflow)
    %{id: id, event: "approved", payload: %{id: 7}, wait_id: request.id}
  end

  defp put_fact(workflow, value, meta) do
    root =
      Enum.find_value(workflow.graph.vertices, fn
        {id, %Workflow.Root{}} -> id
        _ -> nil
      end)

    fact = Fact.new(value: value, meta: meta, ancestry: {root, nil})

    runnable =
      root
      |> Runnable.new(Workflow.root(), fact, %CausalContext{})
      |> Runnable.complete(nil, [FactProduced.new(fact, producer_label: :state_produced)])

    Workflow.apply_runnable(workflow, runnable)
  end

  @tag obligation: ["jido.agent_server.durable_turn.I7", "jido.agent_server.durable_turn.I8"]
  test "accepted input survives replay, with equal retries inert and conflicting IDs rejected" do
    workflow = waiting()
    event = input(workflow)
    assert {:ok, accepted} = WaitHost.accept(workflow, event, 101)
    assert Waits.pending(accepted) == Waits.pending(workflow)

    assert [
             %{
               type: :jido_wait_input,
               version: 1,
               input: ^event,
               accepted_at: 101,
               order: 0
             }
           ] =
             for(
               %Fact{meta: %{jido_wait_record: true}, value: value} <-
                 Workflow.facts(accepted),
               value.type == :jido_wait_input,
               do: value
             )

    accepted = accepted |> Workflow.event_log() |> Workflow.from_events()
    assert {:ok, ^accepted} = WaitHost.accept(accepted, event, 102)

    assert {:error, %{details: %{reason: :conflicting_input_id}}} =
             WaitHost.accept(accepted, %{event | payload: %{id: 8}}, 102)

    assert {:ok, resolved} = WaitHost.resolve(accepted, 102)
    assert Waits.pending(resolved) == []
    assert Workflow.is_runnable?(resolved)
    assert {:ok, ^resolved} = WaitHost.resolve(resolved, 103)

    assert {:ok, %{input_id: "one"}} =
             resolved |> Workflow.react_until_satisfied() |> Jido.Exec.result()
  end

  @tag obligation: "jido.agent_server.durable_turn.I7"
  test "unmarked input-shaped facts are not wait receipts" do
    workflow = waiting()
    event = input(workflow)

    decoy = %{
      type: :jido_wait_input,
      version: 1,
      input: %{event | payload: %{id: 8}},
      accepted_at: 100,
      order: 0
    }

    workflow = put_fact(workflow, decoy, %{})
    assert {:ok, _accepted} = WaitHost.accept(workflow, event, 101)
  end

  @tag obligation: "jido.agent_server.durable_turn.I8"
  test "clock rollback cannot put a later accepted event before an earlier event" do
    workflow = waiting()
    assert {:ok, workflow} = WaitHost.accept(workflow, input(workflow, "first"), 200)
    assert {:ok, workflow} = WaitHost.accept(workflow, input(workflow, "second"), 150)
    assert {:ok, workflow} = WaitHost.resolve(workflow, 151)

    assert {:ok, %{input_id: "first", accepted_at: 200}} =
             workflow |> Workflow.react_until_satisfied() |> Jido.Exec.result()
  end

  @tag obligation: "jido.agent_server.durable_turn.I7"
  test "the host rejects stale, unmatched, malformed, and non-portable input" do
    workflow = waiting()
    event = input(workflow)

    assert {:error, %{details: %{reason: :stale_target}}} =
             WaitHost.accept(workflow, %{event | wait_id: "old"}, 101)

    assert {:error, %{details: %{reason: :unmatched_input}}} =
             WaitHost.accept(workflow, %{event | payload: %{id: 8}}, 101)

    assert {:error, %{details: %{reason: :invalid_input}}} =
             WaitHost.accept(workflow, Map.put(event, :extra, true), 101)

    assert {:error, _} = WaitHost.accept(workflow, %{event | payload: %{id: 7, pid: self()}}, 101)
    assert {:error, _} = WaitHost.accept(workflow, event, -1)
    assert {:error, %{details: %{reason: :invalid_clock}}} = WaitHost.resolve(workflow, -1)
  end

  @tag obligation: "jido.agent_server.durable_turn.I7"
  test "every wait input field has an exact boundary" do
    workflow = waiting()
    event = input(workflow)

    invalid = [
      %{event | id: ""},
      %{event | id: :id},
      %{event | event: ""},
      %{event | event: :approved},
      %{event | wait_id: ""},
      %{event | wait_id: :wait},
      %{event | payload: []},
      %{event | payload: MapSet.new()}
    ]

    for input <- invalid do
      assert {:error, %{details: %{reason: :invalid_input}}} =
               WaitHost.accept(workflow, input, 0)
    end

    assert {:error, %{details: %{reason: :unmatched_input}}} =
             WaitHost.accept(workflow, %{event | event: "a"}, 0)

    assert {:error, %{details: %{reason: :stale_target}}} =
             WaitHost.accept(workflow, %{event | wait_id: "w"}, 0)

    assert {:ok, _accepted} = WaitHost.accept(workflow, event, 0)
    assert {:ok, ^workflow} = WaitHost.resolve(workflow, 0)
  end

  @tag obligation: "jido.agent_server.durable_turn.I8"
  test "invalid saved candidates stop wait resolution" do
    workflow = waiting()
    event = input(workflow)

    invalid = %{
      type: :jido_wait_input,
      version: 1,
      input: event,
      accepted_at: -1,
      order: 0
    }

    workflow = put_fact(workflow, invalid, %{jido_wait_record: true})
    assert {:error, _error} = WaitHost.resolve(workflow, 101)
  end

  @tag obligation: "jido.agent_server.durable_turn.I8"
  test "an invalid receipt stops resolution before a later wait" do
    workflow = waiting(ParallelWaits)
    [first, _second] = Waits.pending(workflow)

    invalid = %{
      type: :jido_wait_input,
      version: 1,
      input: %{
        id: "invalid",
        event: hd(first.options).event,
        payload: %{},
        wait_id: first.id
      },
      accepted_at: -1,
      order: 0
    }

    workflow = put_fact(workflow, invalid, %{jido_wait_record: true})
    assert {:error, _error} = WaitHost.resolve(workflow, 101)
  end

  @tag obligation: "jido.agent_server.durable_turn.I11"
  test "the production host supplies a current clock and durable validation" do
    context = WaitHost.context(%{custom: true}, "host", nil)
    assert context.custom
    assert context.__jido_exec_durable__
    assert is_function(context.__jido_wait_host__.clock, 0)
    before = System.system_time(:millisecond)
    assert context.__jido_wait_host__.clock.() >= before
  end

  @tag obligation: "jido.agent_server.durable_turn.I7"
  test "the input limit rejects new receipts but permits equal retries" do
    workflow = waiting()
    event = input(workflow)

    full =
      Enum.reduce(1..1_024, workflow, fn index, current ->
        {:ok, next} = WaitHost.accept(current, %{event | id: Integer.to_string(index)}, 101)
        next
      end)

    assert {:ok, ^full} = WaitHost.accept(full, %{event | id: "1"}, 102)

    assert {:error, %{details: %{reason: :input_limit}}} =
             WaitHost.accept(full, %{event | id: "overflow"}, 102)
  end
end
