Code.require_file("../support/case.exs", __DIR__)

defmodule JidoTest.System.SupervisionTest do
  use JidoTest.System.Case, async: false
  @moduletag :system
  @moduletag adapter: :ets

  alias JidoTest.RecoverableDeliveryAgent, as: Probe

  @tag :research
  test "immediate Jido replacement must wait for the old tree to release its names", c do
    # OTP supervisor reports are disabled by Logger by default. Enable them for
    # this serial probe and restore the exact prior translator configuration.
    %{filters: filters} = :logger.get_primary_config()
    {translator, options} = Keyword.fetch!(filters, :logger_translator)

    :ok =
      :logger.set_primary_config(
        :filters,
        Keyword.put(filters, :logger_translator, {translator, %{options | sasl: true}})
      )

    on_exit(fn -> :logger.set_primary_config(:filters, filters) end)
    server = start_agent(c)
    assert {:ok, _} = Probe.record_and_deliver(server, "saved", 7)
    completed(c, server, %{"saved" => 7})
    assert GenServer.call(c.sink, :records) == %{"saved" => 7}
    id = Jido.AgentServer.agent(server).id
    children = for {_, pid, _, _} <- Supervisor.which_children(c.jido_pid), is_pid(pid), do: pid

    monitors =
      monitor_agent_tree(c, server) ++
        Enum.map([c.jido_pid | children], &{&1, Process.monitor(&1)})

    prior_monitor = Process.monitor(c.jido_pid)
    held = Process.whereis(Jido.task_supervisor_name(c.jido))

    # Hold the old registered child at a scheduler boundary. It cannot consume
    # its parent's EXIT until released; no timing guess or restart-budget change
    # is needed to expose a new Jido tree colliding with that name.
    true = :erlang.suspend_process(held)

    try do
      Process.exit(c.jido_pid, :kill)
      assert_receive {:DOWN, ^prior_monitor, :process, _, :killed}, 10_000
      assert Process.alive?(c.world)
      assert Process.alive?(held)
    after
      if Process.alive?(held), do: :erlang.resume_process(held)
    end

    await_down(monitors)
    jido_name = c.jido

    replacement =
      c.world
      |> Supervisor.which_children()
      |> Enum.find_value(fn
        {^jido_name, pid, _, _} when is_pid(pid) -> pid
        _ -> nil
      end)

    assert is_pid(replacement) and replacement != c.jido_pid
    assert Process.whereis(c.jido) == replacement
    assert Process.whereis(Jido.task_supervisor_name(c.jido)) != held
    assert {:ok, %{state: %{value: 7}}, 2} = load(c, id)
    refute Process.alive?(c.sink)

    assert Process.alive?(c.world),
           "SYSTEM-SUPERVISION-01: immediate replacement did not preserve the application tree"
  end
end
