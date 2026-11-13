defmodule Jido.Persistence.MixTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Jido.Persistence
  alias Jido.Persistence.{Codec, Config, File}
  alias Jido.Test.Persistence.CLIInstance, as: ConfiguredInstance
  alias Jido.Test.AgentServer.Fixtures.CounterAgent

  test "stdout export contains only JSONL records" do
    path = Path.join(System.tmp_dir!(), "jido-mix-export-#{System.unique_integer([:positive])}")
    on_exit(fn -> Elixir.File.rm_rf!(path) end)

    {:ok, config} = Config.open(store: {File, path: path}, codec: Codec.JSON)
    agent = CounterAgent.instantiate!(id: "exported-agent", state: %{count: 3})
    assert :ok = Persistence.save_agent(config, agent, namespace: "mix-export")

    Mix.Task.reenable("jido.persistence.export")

    output =
      capture_io(fn ->
        Mix.Tasks.Jido.Persistence.Export.run([
          "--adapter",
          "Jido.Persistence.File",
          "--path",
          path,
          "--codec",
          "json",
          "--prefix",
          "jido:agent:v3:",
          "--output",
          "-"
        ])
      end)

    lines = String.split(output, "\n", trim: true)
    assert length(lines) == 1
    assert Enum.all?(lines, &match?({:ok, %{"key" => _, "record" => _}}, JSON.decode(&1)))
    refute output =~ "exported 1 records"
  end

  test "exact inspection emits redacted JSON and does not start the configured instance" do
    :code.purge(ConfiguredInstance)
    :code.delete(ConfiguredInstance)
    refute Code.loaded?(ConfiguredInstance)

    config = Jido.Persistence.CLI.config!(instance: Atom.to_string(ConfiguredInstance))
    assert Code.loaded?(ConfiguredInstance)
    agent = CounterAgent.instantiate!(id: "inspected-agent", state: %{count: 8})
    assert :ok = Persistence.save_agent(config, agent, namespace: "mix-task-instance")
    address = Jido.Agent.Address.new!(namespace: "mix-task-instance", id: agent.id)

    refute Process.whereis(ConfiguredInstance)

    output =
      capture_io(fn ->
        Mix.Tasks.Jido.Persistence.Inspect.run([
          "--instance",
          Atom.to_string(ConfiguredInstance),
          "--key",
          Persistence.agent_key(address)
        ])
      end)

    assert {:ok, %{"key" => _, "record" => _}} = JSON.decode(String.trim(output))
    assert output =~ "REDACTED"
    refute output =~ "\"count\":8"
    refute Process.whereis(ConfiguredInstance)
    assert {:ok, _bytes, _condition} = Jido.Persistence.Store.read(config.store, Persistence.agent_key(address))
  end

  test "full exact inspection warns on stderr and returns full JSON" do
    path = Path.join(System.tmp_dir!(), "jido-mix-inspect-#{System.unique_integer([:positive])}")
    on_exit(fn -> Elixir.File.rm_rf!(path) end)

    {:ok, config} = Config.open(store: {File, path: path}, codec: Codec.JSON)
    agent = CounterAgent.instantiate!(id: "full-agent", state: %{count: 13})
    assert :ok = Persistence.save_agent(config, agent, namespace: "mix-inspect")
    address = Jido.Agent.Address.new!(namespace: "mix-inspect", id: agent.id)

    stderr =
      capture_io(:stderr, fn ->
        stdout =
          capture_io(fn ->
            Mix.Tasks.Jido.Persistence.Inspect.run([
              "--adapter",
              "Jido.Persistence.File",
              "--path",
              path,
              "--codec",
              "json",
              "--key",
              Persistence.agent_key(address),
              "--full"
            ])
          end)

        send(self(), {:inspect_stdout, stdout})
      end)

    assert_receive {:inspect_stdout, stdout}
    assert {:ok, %{"key" => _, "record" => _}} = JSON.decode(String.trim(stdout))
    assert stdout =~ "count"
    assert stderr =~ "WARNING: output includes full persisted data"
  end
end
