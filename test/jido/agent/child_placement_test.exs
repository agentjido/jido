defmodule JidoTest.Agent.ChildPlacementTest do
  use JidoTest.Case, async: true

  alias Jido.Agent.Directive
  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.ChildPlacement
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

  test "placement retries preserve identity and retirement closes the request", %{jido: jido} do
    opts = child_opts(jido)
    assert {:ok, pid, info} = ChildPlacement.start(node(), jido, opts, :temporary, 1_000)
    assert {:ok, ^info} = Server.creation_info(pid)
    assert {:ok, ^pid, ^info} = ChildPlacement.start_local(jido, opts, :temporary)

    monitor = Process.monitor(pid)
    assert :ok = ChildPlacement.stop(jido, pid, :shutdown, 1_000)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}
    assert {:error, :spawn_request_closed} = ChildPlacement.start_local(jido, opts, :temporary)

    parent = %{opts[:parent] | spawn_ref: {2, make_ref()}}

    assert {:ok, replacement, _} =
             ChildPlacement.start_local(jido, Keyword.put(opts, :parent, parent), :temporary)

    refute replacement == pid
  end

  test "an unrelated request cannot attach an existing child identity", %{jido: jido} do
    opts = child_opts(jido)
    assert {:ok, pid, _} = ChildPlacement.start_local(jido, opts, :temporary)
    parent = %{opts[:parent] | tag: :other, spawn_ref: {2, make_ref()}}

    assert {:error, {:child_identity_in_use, id}} =
             ChildPlacement.start_local(jido, Keyword.put(opts, :parent, parent), :temporary)

    assert id == opts[:id]
    assert Process.alive?(pid)
  end

  test "a missing instance or invalid target produces an explicit placement error", %{jido: jido} do
    assert {:error, :jido_instance_not_running} =
             ChildPlacement.start_local(__MODULE__.Missing, child_opts(jido), :temporary)

    assert {:error, _} =
             ChildPlacement.start_local(
               jido,
               Keyword.put(child_opts(jido), :agent, String),
               :temporary
             )

    assert {:error, {:remote_call_failed, "invalid", :badarg}} =
             ChildPlacement.start("invalid", jido, child_opts(jido), :temporary, 1_000)
  end

  test "dead parents prevent placement and existing children can continue after parent loss", %{
    jido: jido
  } do
    owner = start_supervised!({Elixir.Agent, fn -> :owner end}, id: :owner)
    opts = child_opts(jido)
    opts = Keyword.put(opts, :parent, %{opts[:parent] | pid: owner})
    stop_supervised!(:owner)
    refute ChildPlacement.alive?(owner)
    refute ChildPlacement.alive?(nil)
    assert {:error, :spawn_request_closed} = ChildPlacement.start_local(jido, opts, :temporary)

    next_owner = start_supervised!({Elixir.Agent, fn -> :owner end}, id: :next_owner)
    opts = Keyword.put(opts, :parent, %{opts[:parent] | pid: next_owner})

    assert {:ok, pid, _} =
             ChildPlacement.start_local(
               jido,
               Keyword.put(opts, :on_parent_death, :continue),
               :temporary
             )

    stop_supervised!(:next_owner)
    eventually(fn -> Server.status(pid).runtime.parent == nil end)
    assert Process.alive?(pid)
  end

  test "stop handles a standalone Agent and an already stopped process", %{jido: jido} do
    server = start_supervised!({Server, agent: RemoteCounter})
    ref = Process.monitor(server)
    assert :ok = ChildPlacement.stop_local(jido, server, :normal, 1_000)
    assert_receive {:DOWN, ^ref, :process, ^server, :normal}
    assert {:error, :noproc} = ChildPlacement.stop_local(jido, server, :normal, 1_000)
  end

  defp child_opts(jido) do
    [
      agent: RemoteCounter,
      jido: jido,
      id: "placed-child",
      parent: %{pid: self(), id: "parent", tag: :worker, spawn_ref: {1, make_ref()}},
      register: true
    ]
  end
end
