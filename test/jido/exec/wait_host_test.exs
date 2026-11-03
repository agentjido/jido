defmodule Jido.Exec.WaitHostTest do
  use ExUnit.Case, async: false
  @moduletag capture_log: true
  alias Jido.Exec
  alias Jido.Exec.Test.WaitHost, as: Waits
  alias Jido.Flow
  alias Jido.Flow.Ref

  defmodule Echo do
    use Jido.Action, name: "review_echo"
    def run(params, _context), do: {:ok, params}
  end

  defmodule HandOff do
    use Jido.Action, name: "review_handoff"
    def run(params, _context), do: {:handoff, params, Echo}
  end

  defmodule ReadContext do
    use Jido.Action, name: "review_context"
    def run(_params, %{tenant: tenant}), do: {:ok, %{tenant: tenant}}
  end

  defmodule Normalize do
    use Jido.Action, name: "review_normalize"
    def on_before_validate_params(params), do: {:ok, Map.update(params, :n, 1, &(&1 + 1))}
    def run(params, _context), do: {:ok, params}
  end

  defmodule NonportableInput do
    use Jido.Flow, name: "review_nonportable_input"
    def on_before_validate_params(params), do: {:ok, Map.put(params, :pid, self())}

    flow do
      await "event", event: "go", match: %{pid: input(:pid)}
      output result("event")
    end
  end

  defmodule External do
    use Jido.Action, name: "review_external"

    def run(_params, %{counter: counter}) do
      Agent.update(counter, &(&1 + 1))
      {:ok, %{}}
    end
  end

  defmodule WaitingChild do
    use Jido.Flow, name: "review_waiting_child"

    flow do
      step "external", action: External, params: %{}
      await "event", event: "go", needs: ["external"]
      output result("event")
    end
  end

  defmodule SelectWait do
    use Jido.Action, name: "review_select_wait"
    def run(params, _context), do: {:continue, params, WaitingChild}
  end

  defmodule KillCaller do
    use Jido.Action, name: "review_kill_caller"
    def run(_params, _context), do: Process.exit(self(), :kill)
  end

  defmodule ContinueEcho do
    use Jido.Action, name: "review_continue_echo"
    def run(params, _context), do: {:continue, params, Echo}
  end

  defmodule RuntimeFlowHandoff do
    use Jido.Action, name: "review_runtime_flow_handoff"

    def run(_params, _context) do
      target =
        Flow.new!(%{
          name: "runtime_successor",
          components: [
            %{kind: :step, name: "echo", action: Echo}
          ],
          output: Ref.result("echo")
        })

      {:handoff, %{}, target}
    end
  end

  defp handoff(needs \\ []) do
    %{kind: :handoff, name: "handoff", selector: HandOff, needs: needs}
  end

  defp wait_handoff do
    Flow.new!(%{
      name: "wait_handoff",
      components: [
        %{kind: :await, name: "event", event: "go"},
        handoff(["event"])
      ],
      output: Ref.result("handoff")
    })
  end

  defp event(request, id, name \\ "go", payload \\ %{}) do
    %{id: id, wait_id: request.id, event: name, payload: payload}
  end

  test "a wait completes with a standard handoff result" do
    assert {:ok, wf} =
             Waits.start("supported", wait_handoff(), %{}, %{}, now: 0)

    {:waiting, [request]} = Waits.status(wf)

    assert {:ok, done} =
             Waits.accept(wf, event(request, "go"), %{}, now: 1)

    assert {:complete, {:handoff, _, _}} = Waits.status(done)
  end

  test "Handoff terminal constraints reject downstream, wrapped, ignored, and multiple outcomes" do
    for {components, output} <- [
          {[handoff(), %{kind: :step, name: "after", action: Echo, needs: ["handoff"]}], Ref.result("after")},
          {[handoff()], %{request: Ref.result("handoff")}},
          {[handoff()], %{}},
          {[handoff(), %{handoff() | name: "second"}], Ref.result("handoff")}
        ] do
      assert {:error, _} =
               Flow.new(%{name: "invalid_terminal", components: components, output: output})
    end
  end

  test "Waits preserves the context in a bound Instruction" do
    instruction = Jido.Instruction.new!(target: ReadContext, context: %{tenant: "tenant-1"})
    assert {:ok, %{tenant: "tenant-1"}} = Exec.run(instruction)
    assert {:ok, wf} = Waits.start("bound-context", instruction, %{}, %{}, now: 0)
    assert {:complete, {:ok, %{tenant: "tenant-1"}}} = Waits.status(wf)
  end

  test "Waits validates root Action input once" do
    assert {:ok, %{n: 1}} = Exec.run(Normalize)
    assert {:ok, wf} = Waits.start("normalize", Normalize, %{}, %{}, now: 0)
    assert {:complete, {:ok, %{n: 1}}} = Waits.status(wf)
  end

  test "Waits rejects nonportable root params from a bound Instruction" do
    flow =
      Flow.new!(%{
        name: "bound_params",
        components: [
          %{kind: :await, name: "event", event: "go"}
        ],
        output: Ref.result("event")
      })

    instruction = Jido.Instruction.new!(target: flow, params: %{pid: self()})
    assert {:error, _} = Waits.start("bound-params", instruction, %{}, %{}, now: 0)
  end

  test "Waits checks portability after Flow input validation" do
    assert {:error, _} = Waits.start("validated-params", NonportableInput, %{}, %{}, now: 0)
  end

  test "unmatched active input cannot block the event that resolves a wait" do
    flow =
      Flow.new!(%{
        name: "pressure",
        components: [
          %{kind: :await, name: "event", event: "go"}
        ],
        output: Ref.result("event")
      })

    {:ok, wf} = Waits.start("pressure", flow, %{}, %{}, now: 0, max_buffered_inputs: 1)
    {:waiting, [request]} = Waits.status(wf)

    assert {:error, %{details: %{reason: :unmatched_input}}} =
             Waits.accept(wf, event(request, "junk", "unmatched"), %{}, now: 1)

    assert {:ok, done} = Waits.accept(wf, event(request, "valid"), %{}, now: 2)
    assert {:complete, {:ok, %{}}} = Waits.status(done)
  end

  test "the default buffer rejects repeated unmatched events without retaining them" do
    flow =
      Flow.new!(%{
        name: "default_pressure",
        components: [
          %{kind: :await, name: "event", event: "go", match: %{accepted: true}}
        ],
        output: Ref.result("event")
      })

    {:ok, wf} = Waits.start("default-pressure", flow, %{}, %{}, now: 0)
    {:waiting, [request]} = Waits.status(wf)
    initial_size = map_size(wf.graph.vertices)

    for index <- 1..129 do
      assert {:error, %{details: %{reason: :unmatched_input}}} =
               Waits.accept(wf, event(request, "junk-#{index}", "go", %{accepted: false}), %{}, now: 1)
    end

    assert map_size(wf.graph.vertices) == initial_size

    assert {:ok, done} =
             Waits.accept(wf, event(request, "accepted", "go", %{accepted: true}), %{}, now: 2)

    assert {:complete, {:ok, %{accepted: true}}} = Waits.status(done)
  end

  test "a full early buffer does not block an active matching event" do
    flow =
      Flow.new!(%{
        name: "early_pressure",
        components: [
          %{kind: :await, name: "active", event: "go"},
          %{kind: :timer, name: "delay", after_ms: 10},
          %{kind: :await, name: "future", event: "later", needs: ["delay"]}
        ],
        output: Ref.result("future")
      })

    {:ok, wf} = Waits.start("early-pressure", flow, %{}, %{}, now: 0, max_buffered_inputs: 1)
    {:waiting, requests} = Waits.status(wf)
    active = Enum.find(requests, &(&1.path == ["active"]))
    early = %{id: "early", path: ["future"], event: "later", payload: %{later: true}}
    {:ok, wf} = Waits.accept(wf, early, %{}, now: 1)
    assert {:ok, wf} = Waits.accept(wf, event(active, "active", "go", %{now: true}), %{}, now: 2)
    assert {:waiting, [%{path: ["delay"]}]} = Waits.status(wf)
  end

  test "Action death after accepted input remains inside the Exec boundary" do
    flow =
      Flow.new!(%{
        name: "accepted_death",
        components: [
          %{kind: :await, name: "event", event: "go"},
          %{kind: :step, name: "kill", action: KillCaller, needs: ["event"]}
        ],
        output: Ref.result("kill")
      })

    {:ok, wf} = Waits.start("accepted-death", flow, %{}, %{}, now: 0)
    {:waiting, [request]} = Waits.status(wf)

    assert {:error, %Jido.Error.ExecutionError{phase: :execution_task}} =
             Waits.accept(wf, event(request, "kill"), %{}, now: 1)
  end

  test "map timer and await forms require fields for their declared kind" do
    for component <- [
          %{kind: :timer, name: "wrong", event: "go"},
          %{kind: :await, name: "wrong", after_ms: 10}
        ] do
      assert {:error, _} =
               Flow.new(%{
                 name: "wrong_kind",
                 components: [component],
                 output: Ref.result("wrong")
               })
    end
  end

  test "malformed selection option lists return validation errors" do
    assert {:error, _} =
             Flow.new(%{
               name: "improper",
               components: [
                 %{
                   kind: :selection,
                   name: "bad",
                   options: [%{kind: :timer, name: "t", after_ms: 1} | :bad]
                 }
               ],
               output: Ref.result("bad")
             })
  end

  test "a restored equal snapshot acknowledges an equal save retry" do
    store = Jido.Exec.Test.WaitStore.Memory.new()
    {:ok, wf} = Waits.start("saved", wait_handoff(), %{}, %{}, now: 0)
    assert {:ok, 1} = Jido.Exec.Test.WaitStore.Memory.save("saved", 0, wf, store)
    {:ok, 1, restored} = Jido.Exec.Test.WaitStore.Memory.load("saved", store)
    assert {:ok, 1} = Jido.Exec.Test.WaitStore.Memory.save("saved", 0, restored, store)
    Jido.Exec.Test.WaitStore.Memory.close(store)
  end

  test "an unsupported selected wait is rejected before child Action I/O" do
    counter = start_supervised!({Agent, fn -> 0 end})

    flow =
      Flow.new!(%{
        name: "selected_wait",
        components: [
          %{kind: :invoke, name: "invoke", decision: Echo, expander: SelectWait}
        ],
        output: Ref.result("invoke")
      })

    assert {:error, _} = Exec.run(flow, %{}, %{counter: counter})
    assert Agent.get(counter, & &1) == 0
  end

  test "Waits keeps Action process death inside the Exec error boundary" do
    assert {:error, _} = Exec.run(KillCaller)
    supervisor = start_supervised!(Task.Supervisor)

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Waits.start("kill", KillCaller, %{}, %{}, now: 0)
      end)

    assert {:ok, _structured_result} = Task.yield(task, 2_000)
  end

  test "a continuation still applies the predecessor output schema" do
    flow =
      Flow.new!(%{
        name: "predecessor_schema",
        output_schema: Jido.Joi.object(%{required: Jido.Joi.string()}),
        components: [
          %{kind: :invoke, name: "invoke", decision: Echo, expander: ContinueEcho}
        ],
        output: Ref.result("invoke")
      })

    assert {:error, %{details: %{context: "Flow output"}}} = Exec.run(flow)
  end

  test "repeated equal clock advances do not add pending state" do
    flow =
      Flow.new!(%{
        name: "retention",
        components: [
          %{kind: :timer, name: "delay", after_ms: 7_776_000_000}
        ],
        output: Ref.result("delay")
      })

    {:ok, wf} = Waits.start("retention", flow, %{}, %{}, now: 0)

    after_ticks =
      Enum.reduce(1..100, wf, fn _, current ->
        {:ok, next} = Waits.advance(current, %{}, now: 0)
        next
      end)

    assert map_size(after_ticks.graph.vertices) == map_size(wf.graph.vertices)
  end

  test "handoff supports a validated runtime Flow successor" do
    flow =
      Flow.new!(%{
        name: "runtime_handoff",
        components: [
          %{kind: :handoff, name: "handoff", selector: RuntimeFlowHandoff}
        ],
        output: Ref.result("handoff")
      })

    assert {:handoff, %Jido.Instruction{target: %Flow{}}, []} =
             Exec.run(flow, %{}, %{})
  end
end
