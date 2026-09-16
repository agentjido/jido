defmodule Jido.Plugin.ContractTest do
  use ExUnit.Case, async: true

  alias Jido.Signal

  defmodule CallbackOnlyPlugin do
    def state_spec(_opts), do: :none
  end

  defmodule MarkerOnlyPlugin do
    def __jido_plugin__, do: :agent
    def state_spec(_opts), do: :none
  end

  defmodule RaisingMarkerPlugin do
    def __jido_plugin__, do: raise("invalid marker")
  end

  defmodule AdmissionPlugin do
    use Jido.Plugin, agent_server: __MODULE__.Server
  end

  defmodule AdmissionPlugin.Server do
    use Jido.AgentServer.Plugin

    @impl true
    def admit(_runtime, _admission, opts) do
      case Keyword.fetch!(opts, :mode) do
        :invalid -> :not_a_result
        :accept -> {:ok, :runtime_input}
        :reject -> {:error, :denied}
      end
    end
  end

  defmodule InvalidStateAction do
    use Jido.Action, name: "agent_plugin_invalid_state"

    @impl Jido.Action
    def run(_params, _context), do: {:ok, %{trace: [:invalid]}}
  end

  defmodule ReturnStop do
    use Jido.Action, name: "agent_plugin_stop_directive"

    @impl Jido.Action
    def run(_params, context) do
      {:ok, context.agent_state, [%Jido.Agent.Directive.Stop{}]}
    end
  end

  defmodule FailingAction do
    use Jido.Action, name: "agent_plugin_failure"

    @impl Jido.Action
    def run(_params, _context), do: {:error, :action_failed}
  end

  defmodule OwnedStatePlugin do
    use Jido.Plugin, agent: __MODULE__.Agent
  end

  defmodule OwnedStatePlugin.Agent do
    use Jido.Agent.Plugin

    @impl true
    def state_spec(_opts) do
      schema =
        Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
        |> Zoi.default(%{count: 0})

      {:owned, schema}
    end
  end

  defmodule NilOwnedStatePlugin do
    use Jido.Plugin, agent: __MODULE__.Agent
  end

  defmodule NilOwnedStatePlugin.Agent do
    use Jido.Agent.Plugin

    @impl true
    def state_spec(_opts) do
      {:nil_owned, Zoi.any() |> Zoi.nullable() |> Zoi.default(nil)}
    end
  end

  defmodule OverwriteOwnedState do
    use Jido.Action, name: "agent_plugin_overwrite_owned_state"

    @impl Jido.Action
    def run(_params, context) do
      {:ok, Map.put(context.agent_state, :owned, %{count: 10})}
    end
  end

  defmodule DeleteNilOwnedState do
    use Jido.Action, name: "agent_plugin_delete_nil_owned_state"

    @impl Jido.Action
    def run(_params, context) do
      {:ok, Map.delete(context.agent_state, :nil_owned)}
    end
  end

  defmodule OwnedDirective do
    defstruct value: nil
    def validate(%__MODULE__{}), do: {:ok, %Jido.Agent.Directive.Stop{}}
  end

  defmodule ReturnOwnedDirective do
    use Jido.Action, name: "agent_plugin_owned_directive"

    @impl Jido.Action
    def run(_params, context) do
      {:ok, context.agent_state, [%OwnedDirective{value: :original}]}
    end
  end

  defmodule ReplaceDirectiveTypePlugin do
    use Jido.Plugin, agent: __MODULE__.Agent, agent_server: __MODULE__.Server
  end

  defmodule ReplaceDirectiveTypePlugin.Agent do
    use Jido.Agent.Plugin

    @impl true
    def directives(_opts), do: [OwnedDirective]
  end

  defmodule ReplaceDirectiveTypePlugin.Server do
    use Jido.AgentServer.Plugin

    @impl true
    def dispatch(_runtime, _directive, _context, _opts), do: :ok

    def child_spec(_init) do
      Supervisor.child_spec({Elixir.Agent, fn -> nil end}, id: ReplaceDirectiveTypePlugin)
    end
  end

  defmodule ReducedDirective do
    defstruct []
    def validate(%__MODULE__{} = directive), do: {:ok, directive}
  end

  defmodule ForeignDirective do
    defstruct []
    def validate(%__MODULE__{} = directive), do: {:ok, directive}
  end

  defmodule ReturnMixedDirectives do
    use Jido.Action, name: "agent_plugin_mixed_directives"

    @impl Jido.Action
    def run(_params, context) do
      {:ok, context.agent_state, [%ReducedDirective{}, %ForeignDirective{}]}
    end
  end

  defmodule DirectiveReducerPlugin do
    use Jido.Plugin, agent: __MODULE__.Agent
  end

  defmodule DirectiveReducerPlugin.Agent do
    use Jido.Agent.Plugin

    @impl true
    def state_spec(_opts) do
      {:reducer, Zoi.object(%{seen: Zoi.list(Zoi.atom())}) |> Zoi.default(%{seen: []})}
    end

    @impl true
    def reduce(reduction, _opts) do
      owned = Enum.filter(reduction.directives, &match?(%ReducedDirective{}, &1))
      {:ok, %{reduction.plugin_state | seen: Enum.map(owned, & &1.__struct__)}}
    end

    @impl true
    def directives(_opts), do: [ReducedDirective]
  end

  defmodule ForeignDirectivePlugin do
    use Jido.Plugin, agent: __MODULE__.Agent, agent_server: __MODULE__.Server
  end

  defmodule ForeignDirectivePlugin.Agent do
    use Jido.Agent.Plugin

    @impl true
    def directives(_opts), do: [ForeignDirective]
  end

  defmodule ForeignDirectivePlugin.Server do
    use Jido.AgentServer.Plugin

    @impl true
    def dispatch(_runtime, _directive, _context, _opts), do: :ok

    def child_spec(_init) do
      Supervisor.child_spec({Elixir.Agent, fn -> nil end}, id: ForeignDirectivePlugin)
    end
  end

  defmodule NormalizedDirective do
    defstruct [:value]

    def validate(%__MODULE__{} = directive),
      do: {:ok, %{directive | value: String.trim(directive.value)}}
  end

  defmodule ReturnNormalizedDirective do
    use Jido.Action, name: "agent_plugin_normalized_directive"

    @impl Jido.Action
    def run(_params, context) do
      {:ok, context.agent_state, [%NormalizedDirective{value: "  normalized  "}]}
    end
  end

  defmodule NormalizingDirectivePlugin do
    use Jido.Plugin, agent: __MODULE__.Agent
  end

  defmodule NormalizingDirectivePlugin.Agent do
    use Jido.Agent.Plugin

    @impl true
    def state_spec(_opts) do
      {:normalized,
       Zoi.object(%{value: Zoi.string() |> Zoi.default("")}) |> Zoi.default(%{value: ""})}
    end

    @impl true
    def reduce(reduction, _opts) do
      case Enum.find(reduction.directives, &match?(%NormalizedDirective{}, &1)) do
        %NormalizedDirective{value: value} -> {:ok, %{reduction.plugin_state | value: value}}
        nil -> {:ok, reduction.plugin_state}
      end
    end

    @impl true
    def directives(_opts), do: [NormalizedDirective]
  end

  defmodule UnhandledDirective do
    defstruct []
    def validate(%__MODULE__{} = directive), do: {:ok, directive}
  end

  defmodule MissingValidationDirective do
    defstruct []
  end

  defmodule MissingValidationPlugin do
    use Jido.Plugin, agent: __MODULE__.Agent
  end

  defmodule MissingValidationPlugin.Agent do
    use Jido.Agent.Plugin

    @impl true
    def state_spec(_opts),
      do: {:missing_validation, Zoi.integer() |> Zoi.default(0)}

    @impl true
    def reduce(reduction, _opts), do: {:ok, reduction.plugin_state}

    @impl true
    def directives(_opts), do: [MissingValidationDirective]
  end

  defmodule UnhandledDirectivePlugin do
    use Jido.Plugin, agent: __MODULE__.Agent
  end

  defmodule UnhandledDirectivePlugin.Agent do
    use Jido.Agent.Plugin

    @impl true
    def directives(_opts), do: [UnhandledDirective]
  end

  defmodule DispatchWithoutRuntimePlugin do
    use Jido.Plugin, agent: __MODULE__.Agent, agent_server: __MODULE__.Server
  end

  defmodule DispatchWithoutRuntimePlugin.Agent do
    use Jido.Agent.Plugin

    @impl true
    def directives(_opts), do: [UnhandledDirective]
  end

  defmodule DispatchWithoutRuntimePlugin.Server do
    use Jido.AgentServer.Plugin

    @impl true
    def dispatch(_runtime, _directive, _context, _opts), do: :ok
  end

  defmodule BuiltInDirectivePlugin do
    use Jido.Plugin, agent: __MODULE__.Agent
  end

  defmodule BuiltInDirectivePlugin.Agent do
    use Jido.Agent.Plugin

    @impl true
    def state_spec(_opts), do: {:invalid_owner, Zoi.integer() |> Zoi.default(0)}

    @impl true
    def reduce(reduction, _opts), do: {:ok, reduction.plugin_state}

    @impl true
    def directives(_opts), do: [Jido.Agent.Directive.Stop]
  end

  defmodule InvalidStateAgent do
    use Jido.Agent,
      name: "invalid_state_agent",
      schema: Zoi.object(%{trace: Zoi.list(Zoi.string()) |> Zoi.default([])}),
      routes: [{"invalid.run", InvalidStateAction}]
  end

  defmodule DirectiveAgent do
    use Jido.Agent,
      name: "directive_agent",
      routes: [{"directive.stop", ReturnStop}]
  end

  defmodule FailingAgent do
    use Jido.Agent,
      name: "failing_agent",
      routes: [{"failure.run", FailingAction}]
  end

  defmodule OwnedStateAgent do
    use Jido.Agent,
      name: "owned_state_agent",
      schema: Zoi.object(%{trace: Zoi.list(Zoi.string()) |> Zoi.default([])}),
      routes: [{"owned.overwrite", OverwriteOwnedState}],
      plugins: [OwnedStatePlugin]
  end

  defmodule NilOwnedStateAgent do
    use Jido.Agent,
      name: "nil_owned_state_agent",
      routes: [{"owned.delete_nil", DeleteNilOwnedState}],
      plugins: [NilOwnedStatePlugin]
  end

  defmodule ConflictingStateAgent do
    use Jido.Agent,
      name: "conflicting_state_agent",
      schema: Zoi.object(%{owned: Zoi.map()}),
      plugins: [OwnedStatePlugin]
  end

  defmodule ReplaceDirectiveTypeAgent do
    use Jido.Agent,
      name: "replace_directive_type_agent",
      routes: [{"directive.replace", ReturnOwnedDirective}],
      plugins: [ReplaceDirectiveTypePlugin]
  end

  defmodule DirectiveReducerAgent do
    use Jido.Agent,
      name: "directive_reducer_agent",
      routes: [{"directive.reduce", ReturnMixedDirectives}],
      plugins: [DirectiveReducerPlugin, ForeignDirectivePlugin]
  end

  defmodule NormalizingDirectiveAgent do
    use Jido.Agent,
      name: "normalizing_directive_agent",
      routes: [{"directive.normalize", ReturnNormalizedDirective}],
      plugins: [NormalizingDirectivePlugin]
  end

  test "requires the use Jido.Plugin authoring boundary" do
    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Jido.Plugin.Normalizer.normalize_all([CallbackOnlyPlugin])

    assert message == "Plugin must use an owner-facet Jido.Plugin manifest"
  end

  test "requires validation for each declared Directive type" do
    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Jido.Plugin.Normalizer.normalize_all([MissingValidationPlugin])

    assert message == "Agent Plugin Directive must define validate/1"
  end

  test "requires each Plugin Directive to reduce state or dispatch runtime work" do
    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Jido.Plugin.Normalizer.normalize_all([UnhandledDirectivePlugin])

    assert message == "Agent Plugin Directives must reduce state or dispatch runtime work"
  end

  test "allows typed Directive dispatch without a Plugin process" do
    assert {:ok, [%Jido.Plugin.Spec{dispatch?: true, runtime?: false}]} =
             Jido.Plugin.Normalizer.normalize_all([DispatchWithoutRuntimePlugin])
  end

  test "does not let a Plugin claim a built-in Directive" do
    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Jido.Plugin.Normalizer.normalize_all([BuiltInDirectivePlugin])

    assert message == "Agent Plugin cannot own a built-in Directive"
  end

  test "does not accept a marker without the Jido.Plugin behavior" do
    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Jido.Plugin.Normalizer.normalize_all([MarkerOnlyPlugin])

    assert message == "Plugin must use an owner-facet Jido.Plugin manifest"
  end

  test "contains a Plugin marker fault" do
    assert {:error, %Jido.Error.ExecutionError{message: message}} =
             Jido.Plugin.Normalizer.normalize_all([RaisingMarkerPlugin])

    assert message == "Agent Plugin marker failed"
  end

  test "does not accept legacy Plugin module options" do
    module = "Jido.PluginOptionTest#{System.unique_integer([:positive])}"

    assert_raise ArgumentError, ~r/use Jido.Plugin does not accept options/, fn ->
      Code.compile_string("""
      defmodule #{module} do
        use Jido.Plugin, name: "legacy"
      end
      """)
    end
  end

  test "admission accepts only a runtime input result or an explicit error" do
    agent =
      Jido.Agent.new!(
        name: "plugin_admission_contract",
        schema: Zoi.object(%{trace: Zoi.list(Zoi.string()) |> Zoi.default([])})
      )
      |> Jido.Agent.instantiate!()

    signal = Signal.new!("trace.run", %{trace: []}, source: "/test")
    assert {:ok, command} = Jido.Agent.Command.new(agent, signal)

    assert {:ok, invalid_specs} =
             Jido.Plugin.Normalizer.normalize_all([{AdmissionPlugin, mode: :invalid}])

    assert {:error, %Jido.Error.ExecutionError{} = invalid} =
             Jido.AgentServer.Plugin.Callbacks.admit(command, invalid_specs, %{})

    assert invalid.message == "Agent Server Plugin admit/3 returned an invalid result"

    assert invalid.details == %{
             code: :plugin_invalid_callback_result,
             plugin: AdmissionPlugin,
             facet: AdmissionPlugin.Server,
             result: :not_a_result
           }

    assert {:ok, accept_specs} =
             Jido.Plugin.Normalizer.normalize_all([{AdmissionPlugin, mode: :accept}])

    assert {:ok, accepted} = Jido.AgentServer.Plugin.Callbacks.admit(command, accept_specs, %{})
    assert accepted.plugin_inputs[AdmissionPlugin].runtime == :runtime_input

    assert {:ok, reject_specs} =
             Jido.Plugin.Normalizer.normalize_all([{AdmissionPlugin, mode: :reject}])

    assert {:error, :denied} = Jido.AgentServer.Plugin.Callbacks.admit(command, reject_specs, %{})
  end

  test "validates the complete Action state" do
    agent = InvalidStateAgent.new!()
    signal = Signal.new!("invalid.run", %{}, source: "/test")

    assert {:error, %Jido.Error.ValidationError{}} = InvalidStateAgent.cmd(agent, signal)
  end

  test "validates Directives in offline Agent.cmd/3" do
    agent = DirectiveAgent.new!()
    signal = Signal.new!("directive.stop", %{}, source: "/test")

    assert {:ok, _next_agent, [%Jido.Agent.Directive.Stop{reason: :normal}]} =
             DirectiveAgent.cmd(agent, signal)
  end

  test "preserves an Action error" do
    agent = FailingAgent.new!()
    signal = Signal.new!("failure.run", %{}, source: "/test")

    assert {:error, %Jido.Action.Error.ExecutionFailureError{message: "action_failed"}} =
             FailingAgent.cmd(agent, signal)
  end

  test "does not let validation replace a Directive type" do
    agent = ReplaceDirectiveTypeAgent.new!()
    signal = Signal.new!("directive.replace", %{}, source: "/test")

    assert {:error, %Jido.Error.ValidationError{message: message}} =
             ReplaceDirectiveTypeAgent.cmd(agent, signal)

    assert message == "Agent Directive validation changed its type"
  end

  test "gives a Plugin state reducer only its owned Directives" do
    agent = DirectiveReducerAgent.new!()
    signal = Signal.new!("directive.reduce", %{}, source: "/test")

    assert {:ok, next_agent, [%ReducedDirective{}, %ForeignDirective{}]} =
             DirectiveReducerAgent.cmd(agent, signal)

    assert next_agent.state.reducer.seen == [ReducedDirective]
  end

  test "normalizes a Directive before Plugin state reduction" do
    agent = NormalizingDirectiveAgent.new!()
    signal = Signal.new!("directive.normalize", %{}, source: "/test")

    assert {:ok, next_agent, [%NormalizedDirective{value: "normalized"}]} =
             NormalizingDirectiveAgent.cmd(agent, signal)

    assert next_agent.state.normalized.value == "normalized"
  end

  test "adds Plugin state to the Agent schema without author schema work" do
    agent = OwnedStateAgent.new!()

    assert Keyword.keys(OwnedStateAgent.domain_schema().fields) == [:trace]
    assert Keyword.keys(OwnedStateAgent.schema().fields) == [:trace]
    assert Enum.sort(Keyword.keys(OwnedStateAgent.complete_schema().fields)) == [:owned, :trace]
    assert agent.schema == OwnedStateAgent.schema()
    assert agent.plugins == [{OwnedStatePlugin, []}]
    assert agent.state == %{owned: %{count: 0}, trace: []}
  end

  test "Agent.set/2 changes domain state but not Plugin-owned state" do
    agent = OwnedStateAgent.new!()

    assert {:ok, changed} = Jido.Agent.set(agent, %{trace: ["changed"]})
    assert changed.state == %{owned: %{count: 0}, trace: ["changed"]}

    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Jido.Agent.set(agent, %{owned: %{count: 10}})

    assert message == "Agent.set/2 accepts only domain state keys"
  end

  test "does not let an executable change Plugin-owned state" do
    agent = OwnedStateAgent.new!()
    signal = Signal.new!("owned.overwrite", %{}, source: "/test")

    assert {:error, %Jido.Error.ExecutionError{message: message} = error} =
             OwnedStateAgent.cmd(agent, signal)

    assert message == "Agent executable changed Plugin-owned state"
    assert Jido.Error.code(error) == :plugin_state_owner_violation
  end

  test "uses strict equality for numeric changes in nested Plugin-owned state" do
    assert {:ok, specs} = Jido.Plugin.Normalizer.normalize_all([OwnedStatePlugin])
    original = %{owned: %{count: 1, nested: %{value: 2}}}
    agent = %{OwnedStateAgent.new!() | state: original}
    signal = Signal.new!("owned.pipeline", %{}, source: "/test")

    for changed <- [
          %{owned: %{count: 1.0, nested: %{value: 2}}},
          %{owned: %{count: 1, nested: %{value: 2.0}}}
        ] do
      assert {:error, %Jido.Error.ExecutionError{} = error} =
               Jido.Agent.Plugin.Pipeline.run(
                 {:ok, changed, []},
                 agent,
                 signal,
                 %{},
                 Jido.Agent.Plugin.specs(specs)
               )

      assert error.message == "Agent executable changed Plugin-owned state"
      assert error.details.keys == [:owned]
    end
  end

  test "treats a missing Plugin key and a nil Plugin value as different state" do
    agent = NilOwnedStateAgent.new!()
    signal = Signal.new!("owned.delete_nil", %{}, source: "/test")

    assert agent.state == %{nil_owned: nil}

    assert {:error, %Jido.Error.ExecutionError{message: message}} =
             NilOwnedStateAgent.cmd(agent, signal)

    assert message == "Agent executable changed Plugin-owned state"
  end

  test "rejects unknown state keys and domain state key conflicts" do
    assert {:error, %Jido.Error.ValidationError{}} =
             OwnedStateAgent.new(state: %{owned: %{count: 0}, trace: [], extra: true})

    assert_raise Jido.Error.ValidationError, fn -> ConflictingStateAgent.new!() end
  end
end
