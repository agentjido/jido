defmodule Jido.Exec.ApiTest do
  use Covenant.Case, component: "jido_action.boundary", async: true

  alias Jido.Exec
  alias Jido.Instruction
  alias Jido.Test.Action.Fixtures.Actions.{Add, BasicAction, ErrorAction, ExtrasAction}

  @tag obligation: "jido_action.boundary.I5"
  test "compile/2 returns a real one-node Runic Workflow" do
    assert {:ok, %Runic.Workflow{} = workflow} = Exec.compile(Add)
    assert %Jido.Exec.Node.Action{} = Runic.Workflow.get_component(workflow, "add_one")
  end

  @tag obligation: "jido_action.boundary.I5"
  test "run/4 executes an Action module through Runic" do
    assert Exec.run(Add, %{value: 3, amount: 4}) == {:ok, %{value: 7}}
  end

  @tag obligation: "jido_action.boundary.I5"
  test "run/4 executes a bound Instruction through the same path" do
    instruction = Instruction.new!(target: Add, params: %{amount: 3})

    assert Exec.run(instruction, %{value: 4}) == {:ok, %{value: 7}}
  end

  @tag obligation: "jido_action.boundary.I4"
  test "run/4 returns deferred effects" do
    assert Exec.run(ExtrasAction, %{value: 8}, %{trace_id: "trace-1"}) ==
             {:ok, %{value: 8}, [%{trace_id: "trace-1"}]}
  end

  defmodule CallerProcessAction do
    use Jido.Action,
      name: "caller_process_action",
      schema: Jido.Joi.object(%{value: Jido.Joi.integer()}),
      output_schema: Jido.Joi.map()

    @impl true
    def run(%{value: value}, _context), do: {:ok, %{pid: self(), value: value}, [:effect]}
  end

  @tag obligation: ["jido_action.boundary.I1", "jido_action.boundary.I2"]
  test "run/4 validates an Action outside the calling process" do
    assert {:ok, %{pid: pid, value: 8}, [:effect]} =
             Exec.run(CallerProcessAction, %{value: 8})

    refute pid == self()

    assert {:error, %Jido.Error.ValidationError{}} =
             Exec.run(CallerProcessAction, %{value: "bad"})

    assert {:error, %Jido.Error.ExecutionError{phase: :run}} =
             Exec.run(ErrorAction, %{error_type: :runtime})
  end

  @tag obligation: "jido_action.boundary.I5"
  test "caller Instruction metadata does not select Flow execution behavior" do
    instruction =
      Instruction.new!(
        target: Add,
        params: %{value: 1, amount: 2},
        metadata: %{jido_flow: %{component: "c", params: %{}}}
      )

    assert Exec.run(instruction) == {:ok, %{value: 3}}
  end

  @tag obligation: "jido_action.boundary.I6"
  test "invalid compile and Task Supervisor options return configuration errors" do
    assert {:error, %Jido.Error.ValidationError{details: %{option: :name}}} =
             Exec.compile(Add, name: %{})

    flow =
      Jido.Flow.new!(%{
        name: "compile_options",
        components: [%{kind: :step, name: "add", action: Add, params: %{value: 1, amount: 1}}],
        output: Jido.Flow.Ref.result("add")
      })

    for option <- [name: "root", id: :root] do
      assert {:error, %Jido.Error.ValidationError{}} = Exec.compile(flow, [option])
    end

    {:ok, supervisor} = Task.Supervisor.start_link()
    Process.unlink(supervisor)
    monitor = Process.monitor(supervisor)
    Process.exit(supervisor, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^supervisor, :killed}

    assert {:error, %Jido.Error.ValidationError{message: "Task Supervisor is not running"}} =
             Exec.run(Add, %{value: 1, amount: 1}, %{}, task_supervisor: supervisor)
  end

  @tag obligation: "jido_action.boundary.I1"
  test "run/4 projects validation failures" do
    assert {:error, %Jido.Error.ValidationError{}} =
             Exec.run(BasicAction, %{value: "bad"})
  end

  defmodule StructInput do
    defstruct [:id]
  end

  defmodule StructSchemaAction do
    use Jido.Action,
      name: "exec_struct_schema",
      schema: Jido.Joi.struct(StructInput, %{id: Jido.Joi.integer()}, coerce: true)

    @impl true
    def run(%{id: id}, _context), do: {:ok, %{id: id}}
  end

  defmodule AtomSchemaAction do
    use Jido.Action, name: "exec_atom_schema", schema: Jido.Joi.object(%{mode: Jido.Joi.atom()})

    @impl true
    def run(%{mode: mode}, _context), do: {:ok, %{mode: mode}}
  end

  @tag obligation: "jido_action.boundary.I5"
  test "run/4 executes Actions after Joi projects their schemas" do
    assert %{"input_schema" => %{"type" => "object"}} =
             StructSchemaAction.authoring_contract()

    assert Exec.run(StructSchemaAction, %{id: 1}) == {:ok, %{id: 1}}
    assert Exec.run(AtomSchemaAction, %{mode: :fast}) == {:ok, %{mode: :fast}}
    assert {:ok, %Runic.Workflow{}} = Exec.compile(AtomSchemaAction)
  end

  defmodule Fail do
    use Jido.Action, name: "exec_api_fail"

    @impl true
    def run(%{label: label}, _context), do: {:error, label}
  end

  @tag obligation: "jido_action.boundary.I6"
  test "run/4 rejects invalid max_concurrency values" do
    for value <- [0, -1, :bogus, 2.5, nil, "2"] do
      assert {:error, %Jido.Error.ValidationError{details: details}} =
               Exec.run(Add, %{value: 1, amount: 1}, %{}, max_concurrency: value)

      assert details == %{option: :max_concurrency, value: value}
    end
  end

  @tag obligation: "jido_action.boundary.I2"
  test "run/4 reports the same failure for serial and concurrent execution" do
    flow =
      Jido.Flow.new!(%{
        name: "exec_api_two_failures",
        components: [
          %{kind: :step, name: "a", action: Fail, params: %{label: "fail_a"}},
          %{kind: :step, name: "b", action: Fail, params: %{label: "fail_b"}}
        ],
        output: %{a: Jido.Flow.Ref.result("a"), b: Jido.Flow.Ref.result("b")}
      })

    messages =
      for max_concurrency <- [1, 2, 4] do
        assert {:error, error} = Exec.run(flow, %{}, %{}, max_concurrency: max_concurrency)
        Exception.message(error)
      end

    assert [message, message, message] = messages
  end

  @tag obligation: "jido_action.boundary.I2"
  test "run/4 projects Action exceptions" do
    assert {:error, %Jido.Error.ExecutionError{phase: :run}} =
             Exec.run(ErrorAction, %{error_type: :runtime})
  end
end
