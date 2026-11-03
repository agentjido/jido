defmodule Jido.Flow.ParallelTest.DSLFlow do
  @moduledoc false

  use Jido.Flow, name: "parallel_dsl"

  alias JidoActionTest.Fixtures.Actions.{Add, Multiply}

  flow do
    parallel "tools" do
      on_error :fail_fast
      action "add", Add, params: %{value: input(:value), amount: 2}
      action "multiply", Multiply, params: %{value: input(:value), amount: 3}
    end

    output %{"tools" => result("tools")}
  end
end

defmodule Jido.Flow.ParallelTest.InlineDSLFlow do
  @moduledoc false

  use Jido.Flow, name: "parallel_inline_dsl"

  flow do
    parallel "tools" do
      action "add_two", value <- input(:value) do
        {:ok, %{value: value + 2}}
      end

      action "triple",
             value <- input(:value),
             inline: [description: "Multiply a value by three"] do
        {:ok, %{value: value * 3}}
      end
    end

    output %{"tools" => result("tools")}
  end
end

defmodule Jido.Flow.ParallelTest.ReusedInlineNameFlow do
  @moduledoc false

  use Jido.Flow, name: "parallel_reused_inline_name"

  flow do
    parallel "left" do
      action "same", value <- input(:value) do
        {:ok, %{value: value + 1}}
      end
    end

    parallel "right" do
      action "same", value <- input(:value) do
        {:ok, %{value: value * 2}}
      end
    end

    output %{left: result("left"), right: result("right")}
  end
end

defmodule Jido.Flow.ParallelTest do
  use Covenant.Case, component: "jido_action.flow", async: false

  require Runic

  alias Jido.Exec
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias JidoActionTest.Fixtures.Actions.{Add, Multiply}
  alias JidoActionTest.Fixtures.CodecRegistry
  alias JidoActionTest.FlowCodec, as: Codec
  alias Runic.Workflow.SingleOutput.{Context, Result}

  defmodule Fail do
    use Jido.Action, name: "parallel_fail"

    @impl true
    def run(_params, _context), do: {:error, :parallel_failed}
  end

  defmodule Left do
    use Jido.Action, name: "parallel_left"

    @impl true
    def run(_params, %{test_pid: test_pid}) do
      send(test_pid, {:parallel_started, :left, self()})
      receive do: (:release -> {:ok, %{side: :left}, [:left]})
    end
  end

  defmodule Right do
    use Jido.Action, name: "parallel_right"

    @impl true
    def run(_params, %{test_pid: test_pid}) do
      send(test_pid, {:parallel_started, :right, self()})
      receive do: (:release -> {:ok, %{side: :right}, [:right]})
    end
  end

  @tag obligation: "jido_action.flow.I7"
  test "DSL, map authoring, and stored JSON produce one canonical Parallel" do
    direct = parallel_flow()
    assert Jido.Flow.ParallelTest.DSLFlow.flow() == direct

    assert %{
             kind: :parallel,
             actions: [
               %{name: "add", call: %{kind: :action, target: Add}},
               %{name: "multiply", call: %{kind: :action, target: Multiply}}
             ],
             on_error: :fail_fast
           } = direct.components["tools"]

    assert {:ok, document} = Codec.encode(direct, CodecRegistry.mixed())
    assert [component] = document["components"]
    assert component["kind"] == "parallel"
    assert Enum.map(component["actions"], & &1["name"]) == ["add", "multiply"]
    assert {:ok, ^direct} = Codec.decode(document, CodecRegistry.mixed())

    assert Exec.run(direct, %{value: 4}) ==
             {:ok,
              %{
                "tools" => [
                  %{name: "add", value: %{value: 6}},
                  %{name: "multiply", value: %{value: 12}}
                ]
              }}
  end

  @tag obligation: "jido_action.flow.I7"
  test "Parallel inline declarations compile to ordinary Action nodes" do
    flow = Jido.Flow.ParallelTest.InlineDSLFlow.flow()
    workflow = Exec.compile!(flow)

    targets =
      flow.components["tools"].actions
      |> Enum.map(& &1.call.target)

    assert Enum.all?(targets, &Spark.implements_behaviour?(&1, Jido.Action))

    assert Enum.all?(targets, fn target ->
             match?(
               {Jido.Flow.ParallelTest.InlineDSLFlow, [host: Jido.Flow, parallel: "tools", action: _, role: :action]},
               target.__jido_inline_action__()
             )
           end)

    graph_targets =
      workflow.graph.vertices
      |> Enum.map(&elem(&1, 1))
      |> Enum.filter(&match?(%Jido.Exec.Node.Action{}, &1))
      |> Enum.map(& &1.instruction.target)

    assert Enum.sort(graph_targets) == Enum.sort(targets)

    assert Exec.run(flow, %{value: 4}) ==
             {:ok,
              %{
                "tools" => [
                  %{name: "add_two", value: %{value: 6}},
                  %{name: "triple", value: %{value: 12}}
                ]
              }}
  end

  @tag obligation: "jido_action.flow.I7"
  test "inline Action identity includes its parent Parallel name" do
    flow = Jido.Flow.ParallelTest.ReusedInlineNameFlow.flow()
    left = flow.components["left"].actions |> List.first() |> get_in([:call, :target])
    right = flow.components["right"].actions |> List.first() |> get_in([:call, :target])

    assert left != right

    assert left.__jido_inline_action__() ==
             {Jido.Flow.ParallelTest.ReusedInlineNameFlow,
              [host: Jido.Flow, parallel: "left", action: "same", role: :action]}

    assert right.__jido_inline_action__() ==
             {Jido.Flow.ParallelTest.ReusedInlineNameFlow,
              [host: Jido.Flow, parallel: "right", action: "same", role: :action]}

    assert Exec.run(flow, %{value: 3}) ==
             {:ok,
              %{
                left: [%{name: "same", value: %{value: 4}}],
                right: [%{name: "same", value: %{value: 6}}]
              }}
  end

  @tag obligation: "jido_action.flow.I7"
  test "the compiled graph keeps each Action visible and rebuilds" do
    flow = parallel_flow()
    workflow = Exec.compile!(flow)

    actions =
      workflow.graph.vertices
      |> Enum.map(&elem(&1, 1))
      |> Enum.filter(&match?(%Jido.Exec.Node.Action{}, &1))

    assert Enum.map(actions, & &1.instruction.target) |> Enum.sort() == Enum.sort([Add, Multiply])

    rebuilt = workflow |> Runic.Workflow.build_log() |> Runic.Workflow.from_log()

    assert rebuilt_result(rebuilt, %{value: 5}) ==
             {:ok,
              %{
                "tools" => [
                  %{name: "add", value: %{value: 7}},
                  %{name: "multiply", value: %{value: 15}}
                ]
              }}
  end

  @tag obligation: "jido_action.flow.I7"
  test "Parallel starts all Actions before it joins ordered results and effects" do
    test_pid = self()

    flow =
      Flow.new!(%{
        name: "parallel_concurrency",
        components: [
          %{
            kind: :parallel,
            name: "both",
            actions: [
              %{name: "left", action: Left},
              %{name: "right", action: Right}
            ]
          }
        ],
        output: %{both: Ref.result("both")}
      })

    task =
      Task.async(fn ->
        Exec.run(flow, %{}, %{test_pid: test_pid}, max_concurrency: 2)
      end)

    started =
      Enum.map(1..2, fn _index ->
        assert_receive {:parallel_started, side, pid}, 1_000
        {side, pid}
      end)

    assert started |> Enum.map(&elem(&1, 0)) |> Enum.sort() == [:left, :right]

    started
    |> Enum.sort_by(fn {side, _pid} -> side end, :desc)
    |> Enum.each(fn {_side, pid} -> send(pid, :release) end)

    assert Task.await(task, 2_000) ==
             {:ok,
              %{
                both: [
                  %{name: "left", value: %{side: :left}},
                  %{name: "right", value: %{side: :right}}
                ]
              }, [:left, :right]}
  end

  @tag obligation: "jido_action.flow.I7"
  test "Parallel can collect named Action errors as ordered data" do
    flow =
      Flow.new!(%{
        name: "parallel_errors",
        components: [
          %{
            kind: :parallel,
            name: "tools",
            on_error: :collect_errors,
            actions: [
              %{name: "add", action: Add, params: %{value: 2, amount: 3}},
              %{name: "fail", action: Fail}
            ]
          }
        ],
        output: %{tools: Ref.result("tools")}
      })

    assert {:ok,
            %{
              tools: [
                %{name: "add", status: :ok, value: %{value: 5}},
                %{name: "fail", status: :error, error: error}
              ]
            }} = Exec.run(flow, %{})

    assert error.type == :execution_error
    assert error.message == "parallel_failed"
    assert error.details.node == "tools"
    assert error.details.action_index == 1
    assert error.details.action_name == "fail"
    assert error.details.target == Fail
    refute Map.has_key?(error.details, :stacktrace)
  end

  @tag obligation: "jido_action.flow.I7"
  test "Parallel fail-fast errors identify the authored Action" do
    flow =
      Flow.new!(%{
        name: "parallel_fail_fast",
        components: [
          %{
            kind: :parallel,
            name: "tools",
            actions: [
              %{name: "add", action: Add, params: %{value: 2, amount: 3}},
              %{name: "fail", action: Fail}
            ]
          }
        ],
        output: %{tools: Ref.result("tools")}
      })

    assert {:error, error} = Exec.run(flow, %{}, %{}, max_concurrency: 2)
    assert error.details.node == "tools"
    assert error.details.node_path == ["tools", "fail"]
    assert error.details.action_index == 1
    assert error.details.action_name == "fail"
  end

  @tag obligation: "jido_action.flow.I7"
  test "Parallel collects parameter reference failures under the named Action" do
    flow =
      Flow.new!(%{
        name: "parallel_reference_error",
        components: [
          %{
            kind: :parallel,
            name: "tools",
            on_error: :collect_errors,
            actions: [
              %{name: "missing", action: Add, params: %{value: Ref.input(:missing), amount: 1}}
            ]
          }
        ],
        output: %{tools: Ref.result("tools")}
      })

    assert {:ok,
            %{
              tools: [
                %{name: "missing", status: :error, error: error}
              ]
            }} = Exec.run(flow, %{})

    assert error.type == :execution_error
    assert error.details.action_index == 0
    assert error.details.action_name == "missing"
    assert error.details.target == Add
  end

  @tag obligation: "jido_action.flow.I7"
  test "Parallel joins all referenced upstream components before it starts its Actions" do
    flow =
      Flow.new!(%{
        name: "parallel_dependencies",
        components: [
          %{kind: :step, name: "add", action: Add, params: %{value: 2, amount: 3}},
          %{
            kind: :step,
            name: "multiply",
            action: Multiply,
            params: %{value: 2, amount: 4}
          },
          %{
            kind: :parallel,
            name: "combine",
            actions: [
              %{
                name: "from_add",
                action: Add,
                params: %{value: Ref.result("add", :value), amount: 1}
              },
              %{
                name: "from_multiply",
                action: Multiply,
                params: %{value: Ref.result("multiply", :value), amount: 2}
              }
            ]
          }
        ],
        output: %{combined: Ref.result("combine")}
      })

    assert {:ok, dependencies} = Flow.dependencies(flow)
    assert dependencies["combine"].effective == ["add", "multiply"]

    assert Exec.run(flow, %{}) ==
             {:ok,
              %{
                combined: [
                  %{name: "from_add", value: %{value: 6}},
                  %{name: "from_multiply", value: %{value: 16}}
                ]
              }}
  end

  @tag obligation: "jido_action.flow.I7"
  test "Parallel requires a non-empty list with unique named Actions" do
    for actions <- [
          [],
          42,
          [%{name: "same", action: Add} | :improper],
          [%{name: "same", action: Add}, %{name: "same", action: Multiply}]
        ] do
      assert {:error, %Jido.Error.ValidationError{}} =
               Flow.new(%{
                 name: "invalid_parallel",
                 components: [%{kind: :parallel, name: "tools", actions: actions}],
                 output: %{tools: Ref.result("tools")}
               })
    end
  end

  @tag obligation: "jido_action.flow.I7"
  test "the Parallel DSL accepts only Action declarations" do
    for declaration <- [
          ~s|step "nested", action: JidoActionTest.Fixtures.Actions.Add, params: %{}|,
          ~s|map "nested", collection: [], action: JidoActionTest.Fixtures.Actions.Add, params: %{}|,
          ~s|parallel "nested", do: action("work", JidoActionTest.Fixtures.Actions.Add, params: %{})|,
          ~s|flow(do: output(%{}))|
        ] do
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert_raise CompileError, fn ->
          compile_parallel("""
          parallel "tools" do
            #{declaration}
          end
          """)
        end
      end)
    end

    assert_raise CompileError, ~r/use only inline: and do:/, fn ->
      compile_parallel("""
      parallel "tools" do
        action "nested", value <- input(:value), needs: [] do
          {:ok, %{value: value}}
        end
      end
      """)
    end
  end

  @tag obligation: "jido_action.flow.I7"
  test "a wrong Parallel Action target points to its declaration" do
    error =
      assert_raise CompileError, ~r/wrong target kind/, fn ->
        compile_parallel("""
        parallel "tools" do
          action "nested", JidoActionTest.Fixtures.NestedFlow, params: %{}
        end
        """)
      end

    assert error.file == "parallel_dsl.ex"
    assert error.line == 5
  end

  @tag obligation: "jido_action.flow.I7"
  test "Parallel rejects invalid internal join outcomes and supports Runic composition" do
    parallel = parallel_flow() |> Exec.compile!() |> Runic.Workflow.get_component!("tools")

    invalid_shapes = [
      :not_a_list,
      [:not_an_action_outcome],
      [
        {:jido_parallel_action, 0, "add", Jido.Exec.Frame.new(%{}), :invalid},
        {:jido_parallel_action, 1, "multiply", Jido.Exec.Frame.new(%{}), {:ok, %{}, []}}
      ]
    ]

    for input <- invalid_shapes do
      assert %Result{status: :failure, error: error} =
               Jido.Exec.Node.Parallel.run(parallel, input, %Context{})

      assert error.details.reason == :invalid_parallel_outcomes
      assert error.details.node == "tools"
    end

    assert Runic.Component.connectable?(parallel, nil)

    assert %Runic.Workflow{} =
             Jido.Exec.Node.Parallel.connect(parallel, [], Runic.Workflow.new())

    left = Runic.step(fn value -> value end, name: :left)
    right = Runic.step(fn value -> value end, name: :right)
    workflow = Runic.Workflow.new() |> Runic.Workflow.add(left) |> Runic.Workflow.add(right)
    connected = Jido.Exec.Node.Parallel.connect(parallel, [left, right], workflow)

    assert Enum.any?(connected.graph.vertices, fn {_id, node} ->
             match?(
               %Runic.Workflow.Join{joins: [left_hash, right_hash]}
               when left_hash == left.hash and right_hash == right.hash,
               node
             )
           end)
  end

  defp parallel_flow do
    Flow.new!(%{
      name: "parallel_dsl",
      components: [
        %{
          kind: :parallel,
          name: "tools",
          actions: [
            %{name: "add", action: Add, params: %{value: Ref.input(:value), amount: 2}},
            %{
              name: "multiply",
              action: Multiply,
              params: %{value: Ref.input(:value), amount: 3}
            }
          ]
        }
      ],
      output: %{"tools" => Ref.result("tools")}
    })
  end

  defp rebuilt_result(workflow, input) do
    {workflow, observation} =
      Runic.Workflow.execute(workflow, Jido.Exec.Frame.new(input))

    Exec.result(workflow, observation)
  end

  defp compile_parallel(declaration) do
    suffix = System.unique_integer([:positive])

    Code.compile_string(
      """
      defmodule Jido.Flow.ParallelTest.Dynamic#{suffix} do
        use Jido.Flow, name: "parallel_dynamic_#{suffix}"

        flow do
          #{declaration}
          output result("tools")
        end
      end
      """,
      "parallel_dsl.ex"
    )
  end
end
