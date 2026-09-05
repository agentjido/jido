defmodule JidoTest.Agent.ChildPlacementTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Directive
  alias Jido.Examples.{RemoteCounter, RemoteParent}

  test "placement is an explicit validated field and omitted placement stays local" do
    assert {:ok, %{node: nil}} = Directive.validate(Directive.spawn_agent(RemoteCounter, :worker))
    directive = Directive.spawn_agent(RemoteCounter, :worker, node: :worker@host)
    assert {:ok, %{node: :worker@host, opts: %{}}} = Directive.validate(directive)
    assert {:error, _} = Directive.validate(%{directive | node: "worker@host"})
    assert {:error, _} = Directive.validate(%{directive | opts: %{node: :worker@host}})
  end

  test "pure Agent evaluation returns remote intent without starting a process" do
    {:ok, agent} = RemoteParent.new()
    signal = RemoteParent.request_child_signal!(:worker@host)

    assert {:ok, candidate, [%Directive.SpawnAgent{node: :worker@host, tag: :worker}]} =
             RemoteParent.cmd(agent, signal)

    assert candidate == agent
  end
end
