Code.require_file("support.ex", __DIR__)

defmodule JidoTest.AgentServer.StartupTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server2", async: false

  alias Jido.AgentServer, as: Server
  alias Jido.Error.ValidationError
  alias JidoTest.AgentServer.Fixtures, as: F

  setup do
    F.setup_runtime()
  end

  @tag obligation: "jido.agent_server2.I1"
  test "starts with a complete instance and rejects invalid startup", c do
    server = F.start(c)
    F.unchanged(server, c.agent)

    for opts <- [
          nil,
          %{},
          [:bad],
          [],
          [agent: c.agent],
          [agent: c.agent, runner: c.runner, unknown: true],
          [agent: Jido.Agent.definition(c.agent), runner: c.runner],
          [agent: c.agent, runner: c.runner, name: "bad"],
          [agent: c.agent, runner: c.runner, max_postponed_signals: -1]
        ] do
      assert {:error, %ValidationError{}} = Server.start_link(opts)
    end
  end

  @tag obligation: "jido.agent_server2.I1"
  test "rejects an unrelated process under a former Runner name", c do
    name = Module.concat(__MODULE__, "Stale#{System.unique_integer([:positive])}")
    {:ok, pid} = Runic.Runner.start_link(name: name, store: Server.Store)
    assert {Server.Store, _} = Runic.Runner.get_store(name)
    Supervisor.stop(pid)
    fake = start_supervised!(Supervisor.child_spec({Agent, fn -> :fake end}, id: name))
    true = Process.register(fake, name)
    assert {:error, %ValidationError{}} = Server.start_link(agent: c.agent, runner: name)
  end

  @tag obligation: "jido.agent_server2.I2"
  test "configuration rejects typos and invalid values; explicit settings bypass unused defaults",
       c do
    previous = Application.fetch_env(:jido, Server)
    on_exit(fn -> restore_config(previous) end)

    for value <- [
          %{},
          [:invalid],
          [turn_timout: 5],
          [turn_timeout: -1],
          [turn_timeout: 4_294_967_296]
        ] do
      Application.put_env(:jido, Server, value)
      assert {:error, %ValidationError{}} = Server.start_link(agent: c.agent, runner: c.runner)
      server = F.start(c, turn_timeout: :infinity)
      assert {:ok, %{state: %{count: 1}}, []} = Server.call(server, F.signal())
      Server.stop(server)
    end

    for timeout <- [-1, 1.5, :bad, 4_294_967_296] do
      assert {:error, %ValidationError{}} =
               Server.start_link(agent: c.agent, runner: c.runner, turn_timeout: timeout)
    end
  end

  @tag obligation: ["jido.agent_server2.I2", "jido.agent_server2.I17"]
  test "built-in timeout is 60 seconds; global setting is read only at startup", c do
    previous = Application.fetch_env(:jido, Server)
    on_exit(fn -> restore_config(previous) end)
    Application.delete_env(:jido, Server)
    server = F.start(c)
    # Avoid a 60-second test. This assertion protects only default resolution.
    assert {_phase, %{turn_timeout: 60_000}} = :sys.get_state(server)
    Application.put_env(:jido, Server, turn_timeout: 50)
    timed = F.start(c)
    turn = F.blocked(timed, c.runner)
    Application.put_env(:jido, Server, turn_timeout: :infinity)
    assert {:error, :turn_timeout} = Server.await(turn.pending, 1_000)
    F.down(turn.action)
    F.unchanged(timed, c.agent)
    F.clean(c.runner)
    assert {:ok, %{state: %{count: 1}}, []} = Server.call(server, F.signal())
  end

  @tag obligation: "jido.agent_server2.I2"
  test "startup and instance-default errors identify the invalid runtime option", c do
    for {field, value} <- [
          turn_timeout: -1,
          readiness_timeout: :infinity,
          commit_timeout: :infinity,
          directive_timeout: :infinity,
          error_policy_timeout: :infinity,
          max_postponed_signals: -1,
          max_directives_per_turn: -1,
          directive_handler: :bad,
          default_dispatch: :bad,
          debug: :bad,
          debug_max_events: 0
        ] do
      opts = [{field, value}]

      assert {:error, %ValidationError{} = startup_error} =
               Server.start_link(Keyword.merge([agent: c.agent, runner: c.runner], opts))

      assert {:error, %ValidationError{} = defaults_error} = Server.validate_defaults(opts)
      assert startup_error.message =~ Atom.to_string(field)
      assert defaults_error.message =~ Atom.to_string(field)
    end
  end

  @tag obligation: "jido.agent_server2.I2"
  test "runtime settings reject duplicate option keys before startup", c do
    assert {:error, %ValidationError{}} =
             Server.validate_defaults(turn_timeout: 0, turn_timeout: :invalid)

    assert {:error, %ValidationError{}} =
             Server.start_link(
               agent: c.agent,
               runner: c.runner,
               turn_timeout: 0,
               turn_timeout: :invalid
             )
  end

  @tag obligation: "jido.agent_server2.I3"
  test "invalid Signals are rejected by all submission APIs without state loss", c do
    server = F.start(c)

    for input <- [nil, %{}, %{F.signal() | type: nil}, %{F.signal() | id: nil}],
        api <- [:call, :submit, :cast] do
      assert {:error, _} = apply(Server, api, [server, input])
      F.unchanged(server, c.agent)
    end

    F.clean(c.runner)
  end

  @tag obligation: ["jido.agent_server2.I2", "jido.agent_server2.I4"]
  test "request options, reserved context, and finite wait ranges are validated", c do
    server = F.start(c)

    for api <- [:call, :submit, :cast],
        opts <- [
          [unknown: true],
          [context: %{turn_id: "spoof"}],
          [context: %{agent_state: %{count: 99}}],
          [context: :invalid]
        ] do
      assert {:error, _} = apply(Server, api, [server, F.signal(), opts])
    end

    for wait <- [-1, :bad, 4_294_967_296] do
      assert {:error, %ValidationError{}} = Server.call(server, F.signal(), timeout: wait)

      assert {:error, %ValidationError{}} =
               Server.submit(server, F.signal(), admission_timeout: wait)

      assert {:error, %ValidationError{}} = Server.cancel(server, wait)
    end

    F.unchanged(server, c.agent)
  end

  @tag obligation: ["jido.agent_server2.I1", "jido.agent_server2.I2"]
  test "named startup and maximum finite waits remain usable", c do
    name = Module.concat(__MODULE__, "Named#{System.unique_integer([:positive])}")
    server = F.start(c, name: name, turn_timeout: 4_294_967_295)
    assert Process.whereis(name) == server
    pending = Server.submit(name, F.signal(), admission_timeout: 4_294_967_295)
    assert {:ok, %{state: %{count: 1}}, []} = Server.await(pending, 4_294_967_295)

    assert {:ok, %{state: %{count: 2}}, []} =
             Server.call(name, F.signal(), timeout: 4_294_967_295)

    assert %{state_version: 2} = Server.status(name)
    F.clean(c.runner)
  end

  defp restore_config({:ok, value}), do: Application.put_env(:jido, Server, value)
  defp restore_config(:error), do: Application.delete_env(:jido, Server)
end
