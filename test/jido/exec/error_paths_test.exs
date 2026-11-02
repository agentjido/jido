defmodule Jido.Exec.ErrorPathsTest do
  use Covenant.Case, component: "jido_action.boundary", async: true

  alias Jido.Action.Error.{
    ConfigurationError,
    ExecutionFailureError,
    InternalError,
    InvalidInputError
  }

  alias Jido.Exec
  alias Jido.Flow
  alias Jido.Flow.Ref

  alias JidoActionTest.Fixtures.Actions.{
    Add,
    AtomValidationAction,
    InvalidValidationResultAction,
    TupleErrorAction
  }

  defmodule ThrowingValidator do
    @moduledoc false
    @behaviour Jido.Action
    def validate_params(_params), do: throw(:validator_thrown)
    def validate_output(output), do: {:ok, output}
    def run(params, _context), do: {:ok, params}
  end

  defmodule RejectingOutput do
    @moduledoc false
    @behaviour Jido.Action
    def validate_params(params), do: {:ok, params}
    def validate_output(_output), do: {:error, :bad_output}
    def run(params, _context), do: {:ok, params}
  end

  defmodule FailingBody do
    use Jido.Action, name: "error_paths_failing_body"

    @impl true
    def run(_params, _context), do: {:error, "body failed"}
  end

  defmodule Count do
    use Jido.Action, name: "error_paths_count"

    @impl true
    def run(%{count: count}, _context), do: {:ok, %{count: count + 1}}
  end

  defmodule InputFlow do
    use Jido.Flow, name: "error_paths_input", schema: Zoi.object(%{value: Zoi.integer()})

    flow do
      step "add", action: Add, params: %{value: input(:value), amount: 1}
      output result("add")
    end
  end

  describe "run/4 options and targets" do
    @tag obligation: "jido_action.boundary.I6"
    test "invalid option shapes return configuration errors" do
      assert {:error, %ConfigurationError{}} = Exec.run(Add, %{}, %{}, :bad)
      assert {:error, %ConfigurationError{}} = Exec.run(Add, %{}, %{}, bogus: true)

      assert {:error, %ConfigurationError{details: %{reason: :duplicate_option}}} =
               Exec.run(Add, %{}, %{},
                 task_supervisor: Jido.Exec.TaskSupervisor,
                 task_supervisor: Jido.Exec.TaskSupervisor
               )

      assert {:error, %ConfigurationError{}} = Exec.run(Add, %{}, %{}, task_supervisor: 123)

      assert {:error, %ConfigurationError{message: "Task Supervisor lookup failed"}} =
               Exec.run(Add, %{}, %{}, task_supervisor: {:via, :no_such_registry, :name})
    end

    @tag obligation: "jido_action.boundary.I6"
    test "an unknown target and invalid Flow input return structured errors" do
      assert {:error, %ConfigurationError{}} = Exec.run("not a target")

      assert {:error, %InvalidInputError{details: %{phase: :flow_input}}} =
               Exec.run(InputFlow, %{value: "bad"})
    end
  end

  describe "Action validator and callback failures" do
    @tag obligation: "jido_action.boundary.I2"
    test "validator and callback returns become public errors" do
      assert {:error, %InvalidInputError{message: "Action input validation failed"}} =
               Exec.run(AtomValidationAction, %{})

      assert {:error, %InvalidInputError{message: "Action output validation failed"}} =
               Exec.run(RejectingOutput, %{})

      assert {:error, %InternalError{details: %{reason: :invalid_validator_return}}} =
               Exec.run(InvalidValidationResultAction, %{})

      assert {:error, %ExecutionFailureError{details: %{kind: :throw}}} =
               Exec.run(ThrowingValidator, %{})

      assert {:error, %ExecutionFailureError{message: "{:bad, :tuple}"}} =
               Exec.run(TupleErrorAction, %{})
    end
  end

  describe "loop failures" do
    @tag obligation: "jido_action.boundary.I9"
    test "Reduce rejects invalid collections and initial values" do
      reduce = fn collection, initial ->
        flow([
          %{
            kind: :reduce,
            name: "sum",
            collection: collection,
            initial: initial,
            action: Add,
            params: %{value: 1, amount: 1}
          }
        ])
      end

      assert {:error, %{message: "Reduce collection is not enumerable"}} =
               Exec.run(reduce.(Ref.input(:items), %{total: 0}), %{items: 5})

      assert {:error, %{message: "reduce initial value must be a map or Jido.Action.Output"}} =
               Exec.run(reduce.(Ref.input(:items), Ref.input(:initial)), %{items: [1], initial: 5})

      assert {:ok, %{sum: %Jido.Action.Output{kind: :raw}}} =
               Exec.run(reduce.(Ref.input(:items), Ref.input(:initial)), %{
                 items: [],
                 initial: Jido.Action.Output.raw(0)
               })
    end

    @tag obligation: "jido_action.boundary.I9"
    test "loop body failures report their item or iteration position" do
      reduce =
        flow([
          %{
            kind: :reduce,
            name: "sum",
            collection: Ref.input(:items),
            initial: %{},
            action: FailingBody,
            params: %{}
          }
        ])

      assert {:error, %{details: %{item_index: 0, item_id: item_id}}} =
               Exec.run(reduce, %{items: [1]})

      assert is_binary(item_id)

      iterate =
        flow([iterate(FailingBody, %{count: 0}, Jido.Expr.new!(:>=, [Ref.state(:count), 1]), 3)])

      assert {:error, %{details: %{iteration_index: 0, state_revision: 0}}} =
               Exec.run(iterate, %{})
    end

    @tag obligation: "jido_action.boundary.I9"
    test "Iterate rejects invalid State and exhausted limits" do
      never = Jido.Expr.new!(:==, [Ref.state(:count), -1])

      assert {:error, %{message: "flow iterator exhausted maximum iterations"}} =
               Exec.run(flow([iterate(Count, %{count: 0}, never, 2)]), %{})

      assert {:error, %{message: "iterator initial state must resolve to a plain map"}} =
               Exec.run(flow([iterate(Count, Ref.input(:state), never, 2)]), %{state: 1})

      schema = Zoi.map(%{count: Zoi.integer()})

      assert {:error, %{message: "iterator state schema validation failed"}} =
               Exec.run(flow([iterate(Count, Ref.input(:state), never, 2, schema)]), %{
                 state: %{count: "bad"}
               })
    end
  end

  describe "managed execution errors" do
    @tag obligation: "jido_action.boundary.I6"
    test "start, step, resume, and result report invalid requests" do
      runner = :"error_paths_runner_#{System.unique_integer([:positive])}"
      start_supervised!({Runic.Runner, name: runner})

      assert {:error, %ConfigurationError{}} = Exec.start(runner, :id, Add, %{}, %{}, :bad)

      assert {:error, %ConfigurationError{details: %{options: [:bogus]}}} =
               Exec.start(runner, :id, Add, %{}, %{}, bogus: 1)

      # A caller executor replaces the default, and other worker options pass through.
      assert {:ok, _worker} =
               Exec.start(runner, :custom_executor, Add, %{value: 1, amount: 1}, %{},
                 executor: Runic.Runner.Executor.Task,
                 executor_opts: [task_supervisor: Module.concat(runner, TaskSupervisor)],
                 on_complete: nil
               )

      assert {:error, :not_found} = Exec.step(runner, :unknown)
      assert {:error, %InvalidInputError{}} = Exec.resume(runner, :id, :bad_context)
      assert {:error, %ExecutionFailureError{}} = Exec.resume(runner, :unknown, nil)
      assert {:error, %ExecutionFailureError{}} = Exec.resume(runner, :unknown, value: 1)

      assert {:error, %ExecutionFailureError{message: "Exec produced no result"}} =
               Exec.result(Runic.Workflow.new())

      failed = %Runic.Workflow.RunnableFailed{error: :odd_failure}

      assert {:error, %ExecutionFailureError{details: %{reason: :odd_failure}}} =
               Exec.result(%{Runic.Workflow.new() | runnable_events: [failed]})
    end
  end

  describe "compile/2" do
    @tag obligation: "jido_action.boundary.I6"
    test "invalid targets and options return configuration errors" do
      assert {:error, %ConfigurationError{}} = Exec.compile("not a target")
      assert {:error, %ConfigurationError{}} = Exec.compile(Add, :bad)
      assert {:error, %ConfigurationError{}} = Exec.compile(Add, bogus: true)
      assert %Runic.Workflow{} = Exec.compile!(Add, id: :root)
      assert_raise ConfigurationError, fn -> Exec.compile!("not a target") end

      assert_raise ArgumentError, fn ->
        Jido.Exec.Node.Action.new(Jido.Instruction.new!(target: InputFlow))
      end
    end
  end

  defp flow(components) do
    output = Map.new(components, &{String.to_atom(&1.name), Ref.result(&1.name)})
    Flow.new!(%{name: "error_paths", components: components, output: output})
  end

  defp iterate(action, initial, completion, max, schema \\ Zoi.map()) do
    %{
      kind: :iterate,
      name: "loop",
      action: action,
      params: %{count: Ref.state(:count)},
      state: %{initial: initial, update: %{count: Ref.body_result(:count)}, schema: schema},
      completion: completion,
      max_iterations: max
    }
  end
end
