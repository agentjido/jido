defmodule Jido.Exec.ObservationTest do
  use ExUnit.Case, async: true

  alias Jido.Exec
  alias JidoActionTest.Fixtures.Actions.Add
  alias Runic.Workflow

  defmodule WithEffects do
    use Jido.Action, name: "observation_effects"

    @impl true
    def run(params, _context), do: {:ok, params, [:saved]}
  end

  defmodule SometimesFails do
    use Jido.Action, name: "observation_scope"

    @impl true
    def run(%{fail: true}, _context), do: {:error, :first_input_failed}
    def run(params, _context), do: {:ok, params}
  end

  test "a successful new input does not inherit an earlier input's failure" do
    workflow = Exec.compile!(SometimesFails)
    {workflow, first} = Workflow.execute(workflow, %{fail: true})
    assert {:error, _} = Exec.result(workflow, first)

    {workflow, second} = Workflow.execute(workflow, %{fail: false})
    assert Exec.result(workflow, second) == {:ok, %{fail: false}}
  end

  test "observation projects the declared result and preserves effects" do
    workflow = Exec.compile!(WithEffects)
    {workflow, observation} = Workflow.execute(workflow, %{value: 3})
    assert Exec.result(workflow, observation) == {:ok, %{value: 3}, [:saved]}
  end

  test "a running observation cannot return an already produced result" do
    {workflow, observation} = Workflow.execute(Exec.compile!(Add), %{value: 1, amount: 2})
    observation = %{observation | quiescent?: false}

    assert {:error, %Jido.Action.Error.ExecutionFailureError{details: details}} =
             Exec.result(workflow, observation)

    assert details.reason == :execution_active
  end

  test "earlier observations select their own result after another input completes" do
    {workflow, first} = Workflow.execute(Exec.compile!(Add), %{value: 1, amount: 2})
    {workflow, second} = Workflow.execute(workflow, %{value: 5, amount: 2})

    assert Exec.result(workflow, first) == {:ok, %{value: 3}}
    assert Exec.result(workflow, second) == {:ok, %{value: 7}}
  end

  test "an observation cannot select another input's result" do
    {workflow, _first} = Workflow.execute(Exec.compile!(Add), %{value: 1, amount: 2})
    {_other, observation} = Workflow.execute(Exec.compile!(Add), %{value: 5, amount: 2})

    assert {:error, %Jido.Action.Error.ExecutionFailureError{details: details}} =
             Exec.result(workflow, observation)

    assert details.reason == :foreign_execution
  end

  test "stopped admission cannot return a successful output" do
    {workflow, observation} = Workflow.execute(Exec.compile!(Add), %{value: 1, amount: 2})
    observation = %{observation | admission: :stopped}

    assert {:error, %Jido.Action.Error.ExecutionFailureError{details: details}} =
             Exec.result(workflow, observation)

    assert details.reason == :admission_stopped
  end

  test "a computed result does not acknowledge failed persistence" do
    {workflow, observation} = Workflow.execute(Exec.compile!(Add), %{value: 1, amount: 2})

    observation = %{
      observation
      | persistence: %{status: {:error, :storage_unavailable}, event_cursor: 0, pending_events: 1}
    }

    assert Exec.result(workflow, observation) == {:ok, %{value: 3}}
    assert observation.persistence.status == {:error, :storage_unavailable}
  end
end
