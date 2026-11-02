Code.require_file("../support.ex", __DIR__)

defmodule JidoTest.AgentServer.Effects.ProcessTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server.effects", async: false

  import JidoTest.Eventually
  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.Directive.ProcessStart
  alias Jido.AgentServer.Effects
  alias JidoTest.AgentServer.Fixtures, as: F

  defmodule InfoChild do
    def start_link(observer) do
      {:ok, pid} = Agent.start_link(fn -> :ready end)
      send(observer, {:info_child, pid})
      {:ok, pid, :ready}
    end
  end

  defmodule IgnoreChild do
    def start_link, do: :ignore
  end

  defmodule FailedChild do
    def start_link, do: {:error, :controlled_failure}
  end

  setup do
    F.setup_runtime()
  end

  @tag obligation: "jido.agent_server.effects.I11"
  test "ProcessStart validates before commit and starts an independent instance process", c do
    server = F.start(c)

    assert {:error, :jido_instance_required} =
             Server.call(server, batch([%ProcessStart{child_spec: {Agent, fn -> 1 end}}]))

    F.unchanged(server, c.agent)
    instance = F.start(c, jido: c.jido, runner: Jido.exec_runner_name(c.jido))

    assert {:error, :invalid_child_spec} =
             Server.call(instance, batch([%ProcessStart{child_spec: :invalid}]))

    assert {:error, :invalid_child_spec} =
             Server.call(
               instance,
               batch([%ProcessStart{child_spec: %{id: :invalid, start: :invalid}}])
             )

    F.unchanged(instance, c.agent)
    observer = self()

    spec = %{
      id: :spawned,
      start:
        {Agent, :start_link,
         [
           fn ->
             send(observer, {:spawned, self()})
             5
           end
         ]}
    }

    assert {:ok, _, _} = Server.call(instance, batch([%ProcessStart{child_spec: spec}]))
    assert_receive {:spawned, pid}, 1_000

    assert_eventually(
      match?(
        %{phase: :idle, state_version: 1, last_effect_outcome: %{status: :succeeded}},
        Server.status(instance)
      )
    )

    assert Enum.any?(
             DynamicSupervisor.which_children(Jido.agent_supervisor_name(c.jido)),
             &(elem(&1, 1) == pid)
           )

    Server.stop(instance)
    assert Process.alive?(pid)
  end

  @tag obligation: "jido.agent_server.effects.I11"
  test "ProcessStart accepts OTP info and ignore results and reports start failure", c do
    server = F.start(c, jido: c.jido, runner: Jido.exec_runner_name(c.jido))
    failed = %{id: make_ref(), start: {FailedChild, :start_link, []}}

    assert Effects.run(%ProcessStart{child_spec: failed}, nil, %{jido: c.jido}) ==
             {:error, :spawn_process_failed}

    info = %{id: make_ref(), start: {InfoChild, :start_link, [self()]}}
    assert {:ok, _, _} = Server.call(server, batch([%ProcessStart{child_spec: info}]))
    assert_receive {:info_child, pid}, 1_000
    assert Process.alive?(pid)

    assert_eventually(
      match?(
        %{phase: :idle, state_version: 1, last_effect_outcome: %{status: :succeeded}},
        Server.status(server)
      )
    )

    ignore = %{id: make_ref(), start: {IgnoreChild, :start_link, []}}
    assert {:ok, _, _} = Server.call(server, batch([%ProcessStart{child_spec: ignore}]))

    assert_eventually(
      match?(
        %{phase: :idle, state_version: 2, last_effect_outcome: %{status: :succeeded}},
        Server.status(server)
      )
    )

    assert {:ok, _, _} = Server.call(server, batch([%ProcessStart{child_spec: failed}]))

    assert_eventually(
      match?(
        %{phase: :idle, state_version: 3, last_effect_outcome: %{status: :failed}},
        Server.status(server)
      )
    )
  end

  defp batch(directives), do: F.signal(%{mode: :batch, directives: directives})
end
