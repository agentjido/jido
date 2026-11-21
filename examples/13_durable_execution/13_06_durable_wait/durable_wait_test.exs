Code.require_file("durable_wait.ex", __DIR__)

defmodule Jido.Examples.Durable.DurableWaitTest do
  use ExUnit.Case, async: false
  @moduletag :integration
  @moduletag :tmp_dir

  alias Jido.Agent.Address
  alias Jido.AgentServer.{Snapshot, Status, TurnResult}
  alias Jido.Examples.Durable.DurableWait, as: Example

  setup c do
    id = System.unique_integer([:positive])
    instance = :"durable_wait_#{id}"
    namespace = "examples/durable-wait/#{id}"

    start_supervised!(
      {Jido,
       name: instance,
       namespace: namespace,
       persistence: {Jido.Persistence.File, path: c.tmp_dir},
       activation: [idle_residency_timeout: 50]},
      id: instance
    )

    address = Address.new!(namespace: namespace, id: "approval")
    {:ok, ^address} = Jido.create_agent(instance, address, Example)
    %{instance: instance, address: address}
  end

  test "a matching Signal resumes one passivated approval Turn", c do
    {:ok, request} = Example.request_signal(%{request_id: "report-1"})

    assert {:ok,
            %TurnResult{
              status: :waiting,
              turn_id: turn_id,
              agent_activation_id: first_activation_id,
              waits: [wait | _]
            }} =
             Jido.call(c.instance, c.address, request)

    assert is_binary(wait.id)
    eventually(fn -> match?(%Status{residency: :passivated}, Jido.status(c.instance, c.address)) end)

    {:ok, wrong} = Example.resolve_signal(%{request_id: "other", decision: :approve})
    assert {:error, :wait_not_matched} = Jido.call(c.instance, c.address, wrong)

    {:ok, approval} = Example.resolve_signal(%{request_id: "report-1", decision: :approve})

    assert {:ok,
            %TurnResult{
              status: :committed,
              turn_id: ^turn_id,
              agent_activation_id: second_activation_id
            } = completion} =
             Jido.call(c.instance, c.address, approval)

    refute second_activation_id == first_activation_id
    assert {:ok, ^completion} = Jido.call(c.instance, c.address, approval)

    assert %Snapshot{agent: %{state: %{request_id: "report-1", status: :approved}}} =
             snapshot(c)
  end

  test "a cancellation Signal completes the same durable Turn", c do
    {:ok, request} = Example.request_signal(%{request_id: "report-2"})

    assert {:ok, %TurnResult{status: :waiting, turn_id: turn_id}} =
             Jido.call(c.instance, c.address, request)

    {:ok, cancel} = Example.resolve_signal(%{request_id: "report-2", decision: :cancel})

    assert {:ok, %TurnResult{status: :committed, turn_id: ^turn_id}} =
             Jido.call(c.instance, c.address, cancel)

    assert %Snapshot{agent: %{state: %{request_id: "report-2", status: :cancelled}}} =
             snapshot(c)
  end

  defp snapshot(c) do
    {:ok, server} = Jido.activate_agent(c.instance, c.address)
    Jido.AgentServer.snapshot(server)
  end

  defp eventually(fun, attempts \\ 200)
  defp eventually(fun, 0), do: flunk("condition did not become true: #{inspect(fun.())}")

  defp eventually(fun, attempts) do
    case fun.() do
      nil ->
        Process.sleep(10)
        eventually(fun, attempts - 1)

      false ->
        Process.sleep(10)
        eventually(fun, attempts - 1)

      value ->
        value
    end
  end
end
