Code.require_file("../support/case.exs", __DIR__)

defmodule JidoTest.System.SupervisionTest do
  use JidoTest.System.Case, async: false
  @moduletag :system
  @moduletag adapter: :ets

  alias JidoTest.RecoverableDeliveryAgent, as: Probe
  alias JidoTest.System.Observability

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
        Enum.map([c.sink, c.jido_pid | children], &{&1, Process.monitor(&1)})

    parent_monitor = Process.monitor(c.world)
    held = Process.whereis(Jido.task_supervisor_name(c.jido))

    # Hold the old registered child at a scheduler boundary. It cannot consume
    # its parent's EXIT until released; no timing guess or restart-budget change
    # is needed to expose a new Jido tree colliding with that name.
    true = :erlang.suspend_process(held)

    try do
      Process.exit(c.jido_pid, :kill)
      assert_receive {:DOWN, ^parent_monitor, :process, _, reason}, 10_000
      assert reason == :shutdown

      log =
        Observability.await_log(c.observer, fn log ->
          text = inspect(log.msg)
          String.contains?(text, "already_started") or String.contains?(text, "already started")
        end)

      assert inspect(log.msg) =~ inspect(held)
    after
      if Process.alive?(held), do: :erlang.resume_process(held)
    end

    await_down(monitors)
    assert Process.whereis(c.jido) == nil
    assert Process.whereis(Jido.task_supervisor_name(c.jido)) == nil
    assert {:ok, %{state: %{value: 7}}, 2} = load(c, id)
    refute Process.alive?(c.sink)

    assert Process.alive?(c.world),
           "SYSTEM-SUPERVISION-01: immediate replacement exhausted the parent restart budget " <>
             "while an old Jido child retained its registered name. The checkpoint survived, " <>
             "but the application tree did not recover."
  end
end
