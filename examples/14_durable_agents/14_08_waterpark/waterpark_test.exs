Code.require_file("waterpark.ex", __DIR__)

defmodule Jido.Examples.Durable.WaterparkTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.AgentServer.{Snapshot, Status, TurnResult}
  alias Jido.Examples.Durable.Waterpark

  setup do
    path = Path.join(System.tmp_dir!(), "jido_waterpark_#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)

    instance = String.to_atom("waterpark_#{System.unique_integer([:positive])}")
    namespace = "examples/waterpark/#{System.unique_integer([:positive])}"

    start_supervised!(
      {Jido,
       name: instance,
       namespace: namespace,
       persistence: {Jido.Persistence.File, path: path},
       activation: [idle_residency_timeout: 60]},
      id: instance
    )

    %{instance: instance, namespace: namespace}
  end

  test "many durable Agents activate, recover, wait, wake, and passivate in one Instance", c do
    refs = Waterpark.create_guests(c.instance, c.namespace, 20)
    assert Jido.resident_agent_count(c.instance) == 0

    first = hd(refs)

    assert {:ok, %TurnResult{status: :committed, agent_activation_id: warm_id}} =
             Waterpark.visit(c.instance, first)

    assert {:ok, %TurnResult{agent_activation_id: ^warm_id}} = Waterpark.visit(c.instance, first)

    assert {:ok, worker} = Jido.resolve_agent(c.instance, first)
    Process.exit(worker, :kill)

    recovered =
      eventually(fn ->
        case Jido.resolve_agent(c.instance, first) do
          {:ok, pid} when pid != worker -> pid
          _other -> nil
        end
      end)

    assert %Status{agent_activation_id: ^warm_id} = Jido.AgentServer.status(recovered)

    for ref <- refs |> Enum.take(6) |> tl() do
      assert {:ok, %TurnResult{status: :committed}} = Waterpark.visit(c.instance, ref)
    end

    second = Enum.at(refs, 1)
    assert %Snapshot{agent: %{state: %{visits: 1}}} = snapshot(c.instance, second)
    eventually(fn -> Jido.resident_agent_count(c.instance) == 0 end)

    assert {:ok, %TurnResult{agent_activation_id: reactivated_id}} =
             Waterpark.visit(c.instance, first)

    refute reactivated_id == warm_id
    assert %Snapshot{agent: %{state: %{visits: 3}}} = snapshot(c.instance, first)

    approval_ref = Enum.at(refs, 10)

    assert {:ok, %TurnResult{status: :waiting, turn_id: approval_turn}} =
             Waterpark.reserve(c.instance, approval_ref, "cabana-7")

    eventually(fn -> match?(%Status{residency: :passivated}, Jido.status(c.instance, approval_ref)) end)

    assert {:ok, %TurnResult{status: :committed, turn_id: ^approval_turn}} =
             Waterpark.approve(c.instance, approval_ref, "cabana-7", "approval-7")

    assert %Snapshot{agent: %{state: %{status: :approved}}} = snapshot(c.instance, approval_ref)

    timer_ref = Enum.at(refs, 11)
    assert {:ok, %TurnResult{status: :waiting}} = Waterpark.timer(c.instance, timer_ref)
    eventually(fn -> match?(%Status{residency: :passivated}, Jido.status(c.instance, timer_ref)) end)

    eventually(fn ->
      match?(
        %Status{agent_revision: 1},
        Jido.status(c.instance, timer_ref)
      )
    end)

    assert %Snapshot{agent: %{state: %{status: :timer_done}}} = snapshot(c.instance, timer_ref)
    eventually(fn -> Jido.resident_agent_count(c.instance) == 0 end)
  end

  defp snapshot(instance, ref) do
    {:ok, server} = Jido.activate_agent(instance, ref)
    Jido.AgentServer.snapshot(server)
  end

  defp eventually(fun, attempts \\ 300)
  defp eventually(fun, 0), do: flunk("condition did not become true: #{inspect(fun.())}")

  defp eventually(fun, attempts) do
    case fun.() do
      nil -> retry(fun, attempts)
      false -> retry(fun, attempts)
      value -> value
    end
  end

  defp retry(fun, attempts) do
    Process.sleep(10)
    eventually(fun, attempts - 1)
  end
end
