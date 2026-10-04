defmodule JidoTest.ChildTopologyRuntimeAssertions do
  @moduledoc false
  import ExUnit.Assertions
  import JidoTest.TopologyAssertions

  alias Jido.Examples.Research.ChildTopologyRuntime.{Parent, Specifications}

  # Call core APIs directly. The initial failing commit used apply/3 so
  # the same tests could compile before the Runtime module existed.
  def runtime, do: Jido.Topology.Runtime
  def rpc(function, args), do: apply(runtime(), function, args)
  def child_id(parent_id, key \\ :team), do: parent_id <> "/child/" <> to_string(key)

  def opts(jido, id, definition, extra \\ []) do
    Keyword.merge(
      [jido: jido, id: id, topology: definition, director: Parent.owner(), activation: :lazy],
      extra
    )
  end

  def record(value \\ 1),
    do:
      Jido.Signal.new!(Specifications.command(), %{value: value},
        source: "/examples/child-runtime"
      )

  def call_child(jido, id, value \\ 1, options \\ []) do
    rpc(:call, [jido, id, {:child, :team}, record(value), options])
  end

  def stop_runtime(jido, id, pid, expected_agent_count \\ 0) do
    ids = active_ids(jido, id)

    agents =
      for instance <- ids,
          member <- [:director, :alice, :bob],
          server = lookup_agent(jido, instance, member),
          is_pid(server),
          do: server

    resources =
      for instance <- ids,
          function <- [:whereis_runtime, :controller, :whereis_bus],
          args =
            if(function == :whereis_bus, do: [jido, instance, :signals], else: [jido, instance]),
          resource = rpc(function, args),
          is_pid(resource),
          do: resource

    monitors = monitor_runtime(agents, resources)
    assert :ok = Supervisor.stop(pid)
    assert_down(monitors)
    JidoTest.Eventually.eventually(fn -> Jido.agent_count(jido) == expected_agent_count end)
  end

  def kill(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 5_000
  end

  defp lookup_agent(jido, id, :director), do: rpc(:director, [jido, id])
  defp lookup_agent(jido, id, member), do: rpc(:whereis_member, [jido, id, member])

  defp active_ids(jido, id) do
    %{children: children} = rpc(:status, [jido, id])

    descendants =
      for {_key, child} <- children,
          is_pid(rpc(:whereis_runtime, [jido, child.id])),
          descendant <- active_ids(jido, child.id),
          do: descendant

    [id | descendants]
  end
end
