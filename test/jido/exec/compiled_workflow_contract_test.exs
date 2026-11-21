defmodule Jido.Exec.CompiledWorkflowContractTest do
  use ExUnit.Case, async: true

  alias Jido.Exec
  alias Jido.Flow
  alias Jido.Flow.Ref
  alias Jido.Test.Action.Fixtures.Actions.{Add, EchoParamsAction, Multiply}
  alias Runic.Workflow

  defmodule Child do
    use Jido.Flow, name: "compiled_contract_child"

    flow do
      step "add", action: Add, params: %{value: input(:value), amount: 10}
      output result("add")
    end
  end

  defmodule Sum do
    use Jido.Action, name: "compiled_contract_sum"

    @impl true
    def run(%{accumulator: accumulator, item: item}, _context) do
      {:ok, %{total: accumulator.total + item}}
    end
  end

  defmodule Increment do
    use Jido.Action, name: "compiled_contract_increment"

    @impl true
    def run(%{count: count}, _context), do: {:ok, %{count: count + 1}}
  end

  defmodule Decide do
    use Jido.Action, name: "compiled_contract_decide"

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule ContinueToChild do
    use Jido.Action, name: "compiled_contract_continue_to_child"

    @impl true
    def run(params, _context), do: {:continue, params, Child}
  end

  defmodule HandoffTarget do
    use Jido.Action, name: "compiled_contract_handoff_target"

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule SelectHandoff do
    use Jido.Action, name: "compiled_contract_select_handoff"

    @impl true
    def run(params, _context), do: {:handoff, params, HandoffTarget}
  end

  describe "compile/2 canonical Flow permutations" do
    test "single Step compiles to an executable Runic workflow" do
      flow =
        Flow.new!(%{
          name: "compiled_contract_single_step",
          components: [
            %{
              kind: :step,
              name: "add",
              action: Add,
              params: %{value: Ref.input(:value), amount: 2}
            }
          ],
          output: Ref.result("add")
        })

      assert %Flow{} = flow
      assert {:ok, %Workflow{} = workflow} = Exec.compile(flow, [])

      assert %Jido.Exec.Node.Action{
               call: %{kind: :action, target: Add}
             } = Workflow.get_component(workflow, "add")

      {workflow, observation} = Workflow.execute(workflow, %{value: 3})

      assert Exec.result(workflow, observation) == {:ok, %{value: 5}}
    end

    test "two serial Steps compile to a connected Runic chain" do
      flow =
        Flow.new!(%{
          name: "compiled_contract_serial_steps",
          components: [
            %{
              kind: :step,
              name: "add",
              action: Add,
              params: %{value: Ref.input(:value), amount: 2}
            },
            %{
              kind: :step,
              name: "multiply",
              action: Multiply,
              params: %{value: Ref.result("add", :value), amount: 3}
            }
          ],
          output: Ref.result("multiply")
        })

      {workflow, result} = compile_and_execute(flow, %{value: 2})

      assert component_sources(workflow, "multiply") |> Enum.sort() ==
               ["__jido_input__/compiled_contract_serial_steps", "add"]

      assert result == {:ok, %{value: 12}}
    end

    test "independent Steps compile as separate Runic branches" do
      flow =
        Flow.new!(%{
          name: "compiled_contract_independent_steps",
          components: [
            %{
              kind: :step,
              name: "add",
              action: Add,
              params: %{value: Ref.input(:value), amount: 2}
            },
            %{
              kind: :step,
              name: "multiply",
              action: Multiply,
              params: %{value: Ref.input(:value), amount: 3}
            }
          ],
          output: %{add: Ref.result("add"), multiply: Ref.result("multiply")}
        })

      {workflow, result} = compile_and_execute(flow, %{value: 2})
      add_sources = component_sources(workflow, "add")
      multiply_sources = component_sources(workflow, "multiply")

      assert length(add_sources) == 1
      assert add_sources == multiply_sources
      assert result == {:ok, %{add: %{value: 4}, multiply: %{value: 6}}}
    end

    test "a diamond compiles to Runic fan-out and fan-in connections" do
      flow =
        Flow.new!(%{
          name: "compiled_contract_diamond",
          components: [
            %{
              kind: :step,
              name: "seed",
              action: Add,
              params: %{value: Ref.input(:value), amount: 1}
            },
            %{
              kind: :step,
              name: "left",
              action: Add,
              params: %{value: Ref.result("seed", :value), amount: 2}
            },
            %{
              kind: :step,
              name: "right",
              action: Multiply,
              params: %{value: Ref.result("seed", :value), amount: 3}
            },
            %{
              kind: :step,
              name: "merge",
              action: Add,
              params: %{
                value: Ref.result("left", :value),
                amount: Ref.result("right", :value)
              }
            }
          ],
          output: Ref.result("merge")
        })

      {workflow, result} = compile_and_execute(flow, %{value: 1})

      assert component_sources(workflow, "left") |> Enum.sort() ==
               ["__jido_input__/compiled_contract_diamond", "seed"]

      assert component_sources(workflow, "right") |> Enum.sort() ==
               ["__jido_input__/compiled_contract_diamond", "seed"]

      assert component_sources(workflow, "merge") |> Enum.sort() ==
               ["__jido_input__/compiled_contract_diamond", "left", "right"]

      assert result == {:ok, %{value: 10}}
    end

    test "Choice compiles to an executable Runic workflow" do
      flow =
        Flow.new!(%{
          name: "compiled_contract_choice",
          components: [
            %{
              kind: :choice,
              name: "route",
              options: [
                %{
                  name: "positive",
                  condition: Jido.Expr.new!(:>, [Ref.input(:value), 0]),
                  action: Add,
                  params: %{value: Ref.input(:value), amount: 1}
                }
              ],
              fallback: %{
                action: Multiply,
                params: %{value: Ref.input(:value), amount: 2}
              }
            }
          ],
          output: Ref.result("route")
        })

      {_workflow, positive} = compile_and_execute(flow, %{value: 2})
      {_workflow, fallback} = compile_and_execute(flow, %{value: -2})

      assert positive == {:ok, %{value: 3}}
      assert fallback == {:ok, %{value: -4}}
    end

    test "Parallel compiles to an executable Runic workflow" do
      {workflow, result} = compile_and_execute(parallel_flow(), %{value: 2})

      assert %Workflow{} = workflow

      assert result ==
               {:ok,
                %{
                  work: [
                    %{name: "add", value: %{value: 4}},
                    %{name: "multiply", value: %{value: 6}}
                  ]
                }}
    end

    test "Map compiles to an executable Runic workflow" do
      {workflow, result} = compile_and_execute(map_flow(), %{items: [1, 2, 3]})

      assert %Workflow{} = workflow

      assert result ==
               {:ok, %{items: [%{value: 1}, %{value: 2}, %{value: 3}]}}
    end

    test "Reduce compiles to an executable Runic workflow" do
      flow =
        Flow.new!(%{
          name: "compiled_contract_reduce",
          components: [
            %{
              kind: :reduce,
              name: "sum",
              collection: Ref.input(:items),
              initial: %{total: 0},
              action: Sum,
              params: %{accumulator: Ref.accumulator(), item: Ref.item()}
            }
          ],
          output: Ref.result("sum")
        })

      {workflow, result} = compile_and_execute(flow, %{items: [1, 2, 3]})

      assert %Workflow{} = workflow
      assert result == {:ok, %{total: 6}}
    end

    test "Iterate compiles to an executable Runic workflow" do
      flow =
        Flow.new!(%{
          name: "compiled_contract_iterate",
          components: [
            %{
              kind: :iterate,
              name: "count",
              action: Increment,
              params: %{count: Ref.state(:count)},
              state: %{
                initial: %{count: 0},
                update: %{count: Ref.body_result(:count)}
              },
              completion: Jido.Expr.new!(:>=, [Ref.state(:count), 3]),
              max_iterations: 5
            }
          ],
          output: Ref.result("count")
        })

      {workflow, result} = compile_and_execute(flow, %{})

      assert %Workflow{} = workflow

      assert result ==
               {:ok,
                %{
                  kind: :jido_flow_iterate_result,
                  output: %{count: 3},
                  state: %{count: 3},
                  iterations: 3
                }}
    end

    test "a child Flow compiles to an executable Runic workflow" do
      {workflow, result} = compile_and_execute(child_flow(), %{value: 2})

      assert %Workflow{} = workflow

      assert %Jido.Exec.Node.Subflow{child_workflow: %Workflow{}} =
               Workflow.get_component(workflow, "child")

      assert result == {:ok, %{value: 12}}
    end

    test "Invoke compiles to an executable Runic workflow" do
      flow =
        Flow.new!(%{
          name: "compiled_contract_invoke",
          components: [
            %{
              kind: :invoke,
              name: "invoke",
              decision: Decide,
              expander: ContinueToChild,
              params: %{value: Ref.input(:value)}
            }
          ],
          output: Ref.result("invoke")
        })

      {workflow, result} = compile_and_execute(flow, %{value: 2})

      assert %Workflow{} = workflow
      assert result == {:ok, %{value: 12}}
    end

    test "terminal Handoff compiles to a Runic control result" do
      flow =
        Flow.new!(%{
          name: "compiled_contract_handoff",
          components: [
            %{
              kind: :handoff,
              name: "handoff",
              selector: SelectHandoff,
              params: %{value: Ref.input(:value)}
            }
          ],
          output: Ref.result("handoff")
        })

      {workflow, result} = compile_and_execute(flow, %{value: 2})

      assert %Workflow{} = workflow

      assert {:handoff,
              %Jido.Instruction{
                kind: :action,
                target: HandoffTarget,
                params: %{value: 2}
              }, []} = result
    end

    test "Wait compiles to a Runic workflow that resumes with host input" do
      flow =
        Flow.new!(%{
          name: "compiled_contract_wait",
          components: [
            %{
              kind: :await,
              name: "approval",
              event: "approved",
              match: %{id: Ref.input(:id)}
            }
          ],
          output: Ref.result("approval")
        })

      assert {:ok, %Workflow{} = workflow} = Exec.compile(flow, [])

      workflow =
        workflow
        |> Workflow.put_run_context(%{
          _global: Jido.Exec.Runtime.wait_context(%{}, "compiled-contract-wait", 100)
        })
        |> Workflow.react_until_satisfied(%{id: 7})

      assert [request] = Jido.Exec.Runtime.pending_waits(workflow)

      candidate = %{
        input: %{id: "signal-1", event: "approved", payload: %{id: 7}},
        accepted_at: 101,
        order: 0
      }

      assert {:ok, workflow} =
               Jido.Exec.Runtime.resolve_wait(workflow, request.id, [candidate], 101)

      assert {:ok, %{id: 7}} =
               workflow
               |> Workflow.react_until_satisfied()
               |> Jido.Exec.Result.project()
    end

    test "a compiled Runic workflow survives snapshot recovery" do
      flow = serial_flow()
      assert {:ok, workflow} = Exec.compile(flow, [])
      {workflow, observation} = Workflow.execute(workflow, %{value: 2})
      assert Exec.result(workflow, observation) == {:ok, %{value: 8}}

      assert {:ok, restored} =
               workflow
               |> Runic.Runner.encode_snapshot()
               |> Runic.Runner.decode_snapshot()

      assert Jido.Exec.Result.project(restored) == {:ok, %{value: 8}}
    end
  end

  test "run/4 is the compile, Runic execute, and result contract" do
    cases = [
      {Add, %{value: 2, amount: 3}},
      {serial_flow(), %{value: 2}},
      {parallel_flow(), %{value: 2}},
      {map_flow(), %{items: [1, 2, 3]}},
      {child_flow(), %{value: 2}}
    ]

    for {target, input} <- cases do
      assert Exec.run(target, input) == execute_compiled(target, input)
    end
  end

  @tag obligation: "jido_action.execution.I25"
  test "supports?/2 accepts only host-supplied capabilities" do
    assert Exec.supports?(%{jido_exec_capabilities: [:waits]}, :waits)
    refute Exec.supports?(%{jido_exec_capabilities: [:future]}, :future)
    refute Exec.supports?(%{}, :waits)
    refute Exec.supports?(%{jido_exec_capabilities: :waits}, :waits)
    refute Exec.supports?(%{jido_exec_capabilities: [:waits | :invalid]}, :waits)
  end

  test "compile/2 returns a Runic workflow that accepts canonical Flow input directly" do
    flow = serial_flow()

    assert {:ok, %Workflow{} = workflow} = Exec.compile(flow, [])
    {workflow, observation} = Workflow.execute(workflow, %{value: 3})

    assert Exec.result(workflow, observation) == {:ok, %{value: 10}}
  end

  defp execute_compiled(target, input) do
    {:ok, workflow} = Exec.compile(target, [])
    {workflow, observation} = Workflow.execute(workflow, input)
    Exec.result(workflow, observation)
  end

  defp compile_and_execute(flow, input) do
    assert %Flow{} = flow
    assert {:ok, %Workflow{} = workflow} = Exec.compile(flow, [])
    {workflow, observation} = Workflow.execute(workflow, input)
    {workflow, Exec.result(workflow, observation)}
  end

  defp component_sources(workflow, name) do
    graph = Workflow.component_graph(workflow)
    component = Workflow.get_component!(workflow, name)

    graph
    |> Multigraph.in_neighbors(component)
    |> Enum.map(& &1.name)
  end

  defp serial_flow do
    Flow.new!(%{
      name: "compiled_contract_serial",
      components: [
        %{kind: :step, name: "add", action: Add, params: %{value: Ref.input(:value), amount: 2}},
        %{
          kind: :step,
          name: "multiply",
          action: Multiply,
          params: %{value: Ref.result("add", :value), amount: 2}
        }
      ],
      output: Ref.result("multiply")
    })
  end

  defp parallel_flow do
    Flow.new!(%{
      name: "compiled_contract_parallel",
      components: [
        %{
          kind: :parallel,
          name: "work",
          actions: [
            %{name: "add", action: Add, params: %{value: Ref.input(:value), amount: 2}},
            %{name: "multiply", action: Multiply, params: %{value: Ref.input(:value), amount: 3}}
          ]
        }
      ],
      output: %{work: Ref.result("work")}
    })
  end

  defp map_flow do
    Flow.new!(%{
      name: "compiled_contract_map",
      components: [
        %{
          kind: :map,
          name: "items",
          collection: Ref.input(:items),
          action: EchoParamsAction,
          params: %{value: Ref.item()}
        }
      ],
      output: %{items: Ref.result("items")}
    })
  end

  defp child_flow do
    Flow.new!(%{
      name: "compiled_contract_child_parent",
      components: [
        %{kind: :subflow, name: "child", flow: Child, params: %{value: Ref.input(:value)}}
      ],
      output: Ref.result("child")
    })
  end
end
