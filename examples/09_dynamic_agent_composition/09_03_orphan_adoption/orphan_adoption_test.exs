Code.require_file("../support/worker.ex", __DIR__)
Code.require_file("orphan_adoption.ex", __DIR__)

defmodule Jido.Examples.MultiAgent.StableReplacementTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.Agent.Ref
  alias Jido.AgentServer.{Snapshot, TurnResult}
  alias Jido.Examples.{StableReplacement, Worker}

  setup do
    id = System.unique_integer([:positive])
    instance = :"stable_replacement_#{id}"
    namespace = "examples/stable-replacement/#{id}"
    table = :"stable_replacement_store_#{id}"

    start_supervised!(
      {Jido, name: instance, namespace: namespace, persistence: {Jido.Persistence.ETS, table: table}},
      id: instance
    )

    ref = Ref.new!(namespace: namespace, id: "worker")
    {:ok, ^ref} = Jido.create_agent(instance, ref, Worker)
    %{instance: instance, ref: ref}
  end

  test "the Ref resolves a replacement worker and retains committed state", c do
    assert {:ok, %TurnResult{agent_activation_id: activation_id}} =
             StableReplacement.calculate(c.instance, c.ref, "first", 3)

    {:ok, first} = Jido.resolve_agent(c.instance, c.ref)
    Process.exit(first, :kill)

    second =
      eventually(fn ->
        case Jido.resolve_agent(c.instance, c.ref) do
          {:ok, pid} when pid != first -> pid
          _other -> nil
        end
      end)

    assert %Snapshot{agent: %{state: %{completed: [%{value: 6}]}}} =
             Jido.AgentServer.snapshot(second)

    assert activation_id == Jido.AgentServer.status(second).agent_activation_id
  end

  defp eventually(fun, attempts \\ 200)
  defp eventually(fun, 0), do: flunk("condition did not become true: #{inspect(fun.())}")

  defp eventually(fun, attempts) do
    case fun.() do
      value when value in [nil, false] ->
        receive do
        after
          10 -> eventually(fun, attempts - 1)
        end

      value ->
        value
    end
  end
end
