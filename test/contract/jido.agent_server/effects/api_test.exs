defmodule JidoTest.AgentServer.EffectsApiTest do
  use Covenant.Case, component: "jido.agent_server.effects", async: true

  alias Jido.Agent.Directive, as: AgentDirective
  alias Jido.Agent.Directive.Emit
  alias Jido.AgentServer.Directive

  alias Jido.AgentServer.Directive.{
    AgentSend,
    AgentStart,
    AgentStop,
    ErrorReport,
    OwnerSend,
    ProcessStart,
    ServerStop
  }

  alias Jido.AgentServer.Effects
  alias Jido.Dispatch.Preparation
  alias Jido.Signal
  alias JidoTest.AgentEvolutionFixtures, as: E

  @records [AgentSend, AgentStart, AgentStop, ErrorReport, OwnerSend, ProcessStart, ServerStop]

  @tag obligation: "jido.agent_server.effects.I12"
  test "the documented runtime Directive API and public types are exact" do
    assert documented_api(Directive) == [
             {:function, :agent_send, 2},
             {:function, :agent_start, 3},
             {:function, :agent_stop, 2},
             {:function, :error_report, 2},
             {:function, :owner_send, 1},
             {:function, :process_start, 1},
             {:function, :server_stop, 1},
             {:function, :signal_send, 3}
           ]

    assert documented_types(Directive) == [
             {:type, :agent_start_option, 0},
             {:type, :restart_policy, 0},
             {:type, :signal_send_option, 0},
             {:type, :t, 0}
           ]

    assert public_module?(Directive)

    for module <- @records do
      assert public_module?(module)
      assert documented_api(module) == []
      assert documented_types(module) == [{:type, :t, 0}]
    end

    refute public_module?(Effects)
    refute public_module?(Preparation)
  end

  @tag obligation: "jido.agent_server.effects.I12"
  test "runtime Directive constructors keep closed unique options and stable results" do
    signal = Signal.new!("effect.test", %{}, source: "/test")
    formatter = &{:effect, &1}

    assert %Emit{signal: ^signal, dispatch: {:pid, dispatch}} =
             Directive.signal_send(signal, self(),
               delivery_mode: :sync,
               timeout: 100,
               message_format: formatter
             )

    assert dispatch[:target] == self()
    assert dispatch[:delivery_mode] == :sync
    assert dispatch[:timeout] == 100
    assert dispatch[:message_format] == formatter
    assert %AgentSend{name: :child, signal: ^signal} = Directive.agent_send(:child, signal)
    assert %OwnerSend{signal: ^signal} = Directive.owner_send(signal)

    assert %ErrorReport{error: :failed, context: :turn} =
             Directive.error_report(:failed, :turn)

    assert %ProcessStart{child_spec: Task} = Directive.process_start(Task)

    assert %AgentStart{
             agent: __MODULE__,
             name: :child,
             opts: %{id: "child"},
             meta: %{role: :worker},
             restart: :temporary
           } =
             Directive.agent_start(__MODULE__, :child,
               opts: [id: "child"],
               meta: [role: :worker],
               restart: :temporary
             )

    assert %AgentStop{name: :child, reason: :shutdown} =
             Directive.agent_stop(:child, :shutdown)

    assert %ServerStop{reason: :shutdown} = Directive.server_stop(:shutdown)

    for invalid <- [
          [unknown: true],
          [restart: :permanent, restart: :temporary],
          [opts: [id: "first", id: "second"]],
          [meta: %URI{}]
        ] do
      assert_raise ArgumentError, fn -> Directive.agent_start(__MODULE__, :child, invalid) end
    end

    assert_raise ArgumentError, fn ->
      Directive.signal_send(signal, self(), timeout: 10, timeout: 20)
    end
  end

  @tag obligation: ["jido.agent_server.effects.I10", "jido.agent_server.effects.I12"]
  test "hidden validation hooks protect runtime Directive inputs before commit" do
    for policy <- [:permanent, :temporary, :transient] do
      directive = Directive.agent_start(E.Worker, :child, restart: policy)
      assert {:ok, ^directive} = AgentDirective.validate(directive)
      assert :ok = Directive.validate_restart_policy(policy)
    end

    assert {:error, message} = Directive.validate_restart_policy(:invalid)
    assert message != ""

    for key <- [
          :agent,
          :jido,
          :partition,
          :runner,
          :node,
          :lifecycle_mod,
          :pool,
          :pool_key,
          :idle_timeout,
          :persistence,
          :restore,
          :state_version
        ] do
      assert {:error, message} = Directive.validate_agent_start_opts(%{key => :invalid})
      assert message != ""
    end

    assert {:error, message} = Directive.validate_agent_start_opts([])
    assert message != ""

    invalid = %{E.Worker.instantiate!(id: "invalid-effect-target") | state: %{count: :invalid}}
    assert {:error, _} = Directive.validate_agent_target(invalid)
    assert {:error, {:invalid_agent, 42}} = Directive.validate_agent_target(42)
  end

  defp documented_api(module) do
    module
    |> docs()
    |> Enum.flat_map(fn
      {{kind, name, arity}, _, _, doc, _}
      when kind in [:function, :macro] and doc not in [:hidden, :none] ->
        [{kind, name, arity}]

      _other ->
        []
    end)
    |> Enum.sort()
  end

  defp documented_types(module) do
    module
    |> docs()
    |> Enum.flat_map(fn
      {{:type, name, arity}, _, _, doc, _} when doc not in [:hidden, :none] ->
        [{:type, name, arity}]

      _other ->
        []
    end)
    |> Enum.sort()
  end

  defp docs(module) do
    {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(module)
    docs
  end

  defp public_module?(module) do
    {:docs_v1, _, _, _, module_doc, _, _} = Code.fetch_docs(module)
    module_doc not in [:hidden, :none]
  end
end
