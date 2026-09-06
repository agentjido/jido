defmodule Jido.AgentServer.OptionsTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer.{Options, ParentRef}
  alias Jido.Examples.RemoteCounter

  defmodule ZeroArityConstructor do
    def new, do: RemoteCounter.new(id: "zero-arity")
  end

  defmodule FailingConstructor do
    def new(_opts), do: {:error, :constructor_failed}
  end

  defmodule RaisingConstructor do
    def new(_opts), do: raise("constructor failed")
  end

  defmodule InvalidConstructor do
    def new(_opts), do: :invalid
  end

  test "constructors keep their result and report malformed results" do
    assert {:ok, opts} = Options.new(agent: ZeroArityConstructor)
    assert opts.agent.id == "zero-arity"
    assert {:error, :constructor_failed} = Options.new(agent: FailingConstructor)

    assert {:error, %RuntimeError{message: "constructor failed"}} =
             Options.new(agent: RaisingConstructor)

    assert_invalid([agent: InvalidConstructor], "constructor returned an invalid value")
    assert_invalid([agent: String], "must implement new/0 or new/1")
    assert_invalid([agent: JidoTest.MissingAgentModule], "could not be loaded")
    assert_invalid([agent: 42], "agent is required")
  end

  test "definition overrides create an instance while instance overrides are rejected" do
    {:ok, agent} = RemoteCounter.new(id: "original")
    assert {:ok, %{agent: ^agent}} = Options.new(agent: agent)
    assert_invalid([agent: agent, id: "other"], "cannot override an Agent instance")

    assert_invalid(
      [agent: agent, initial_state: %{values: []}],
      "cannot override an Agent instance"
    )

    definition = Jido.Agent.definition(agent)
    assert {:ok, %{agent: instance}} = Options.new(agent: definition, id: "created")
    assert instance.id == "created"
    assert Jido.Agent.instance?(instance)
  end

  test "invalid runtime options produce configuration errors before startup" do
    for {option, fragment} <- [
          {[on_parent_death: :invalid], "on_parent_death is invalid"},
          {[spawn_fun: fn -> :ok end], "spawn_fun must have arity 1"},
          {[error_policy: :invalid], "error_policy is invalid"},
          {[error_policy: {:max_errors, 0}], "error_policy is invalid"},
          {[error_policy: {:emit_signal, nil}], "requires an external dispatch target"},
          {[error_policy: {:emit_signal, :invalid}], "emit_signal dispatch is invalid"},
          {[directive_timeout: 0], "directive_timeout must be"},
          {[restore: true], "restore must be"},
          {[state_version: -1], "state_version must be"},
          {[pool: "invalid"], "pool must be an atom"},
          {[idle_timeout: 0], "idle_timeout must be"},
          {[persistence: :invalid], "persistence adapter is invalid"},
          {[register: true, registry: nil], "requires an Agent Registry"},
          {[register: true, registry: Registry, name: :agent], "cannot be used together"},
          {[directive_handler: fn _ -> :ok end], "does not support custom Directive handlers"},
          {[cron_specs: []], "does not support cron_specs"}
        ] do
      assert_invalid([agent: RemoteCounter] ++ option, fragment)
    end

    assert_invalid([:invalid], "must be a keyword list")
    assert_invalid(:invalid, "must be a map or keyword list")
  end

  test "parent, registration and finite lifecycle options are normalized", %{jido: jido} do
    parent = %{pid: self(), id: "parent", tag: :worker}

    assert {:ok, opts} =
             Options.new(%{
               agent: RemoteCounter,
               jido: jido,
               parent: parent,
               idle_timeout: 100,
               directive_timeout: :infinity,
               spawn_fun: fn _ -> :ignore end,
               error_policy: {:emit_signal, {:pid, target: self()}},
               state_version: 7,
               restore: false
             })

    assert %ParentRef{pid: pid, id: "parent", tag: :worker} = opts.parent
    assert pid == self()
    assert opts.register
    assert opts.registry == Jido.registry_name(jido)
    assert opts.state_version == 7
    assert opts.directive_timeout == :infinity
    assert opts.idle_timeout == 100
    assert opts.restore == false
    assert {:error, _} = Options.new(agent: RemoteCounter, parent: :invalid)
  end

  defp assert_invalid(opts, fragment) do
    assert {:error, %Jido.Error.ValidationError{kind: :config, message: message}} =
             Options.new(opts)

    assert message =~ fragment
  end
end
